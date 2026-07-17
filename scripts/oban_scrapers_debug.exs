# Oban scrapers queue debugger — cryptocompare funding rate / open interest / price.
#
# Diagnoses stuck historical scraper queues: paused without a pending resume,
# rate limited (snoozed), saturated, orphaned `executing` rows from dead pods,
# isolated notifier (pause/resume signals lost), dead cron feed.
#
# Usage on prod:
#   1. Attach to the SCRAPERS pod (the only pod running :oban_scrapers with queues):
#        kubectl exec -it <scrapers-pod> -- bin/sanbase remote
#   2. Paste this entire file into the iex prompt.
#
# READ-ONLY commands:
#   ObanScrapersDebug.report()                 # funding_rate + open_interest overview
#   ObanScrapersDebug.report(:all)             # + price
#   ObanScrapersDebug.deep_dive(:funding_rate) # live processes: stacktraces of executing
#                                              # jobs, stager/sonar/peer, hackney pool
#   ObanScrapersDebug.watch(:funding_rate)     # 1 line / 5s: is the queue moving?
#   ObanScrapersDebug.history(:funding_rate)   # completions & rate-limit hits per hour
#   ObanScrapersDebug.errors(:funding_rate)    # tally of recent job errors
#   ObanScrapersDebug.lag(:funding_rate)       # stalest instruments (exporter progress)
#   ObanScrapersDebug.orphans(:funding_rate)   # executing rows left by dead nodes
#   ObanScrapersDebug.job(4175570)             # dump one job row
#   ObanScrapersDebug.processes()              # all Oban processes + mailboxes
#
# MUTATING commands (explicit, never called by the read-only ones):
#   ObanScrapersDebug.force_resume(:funding_rate)
#   ObanScrapersDebug.cancel_orphans(:funding_rate, confirm: true)  # stale work -> cancelled
#   ObanScrapersDebug.retry_orphans(:funding_rate, confirm: true)   # re-run the work
#   Without `confirm: true` both only print what they would touch.

defmodule ObanScrapersDebug do
  import Ecto.Query

  @conf_name :oban_scrapers
  @add_jobs_worker "Sanbase.Cryptocompare.AddHistoricalJobsWorker"
  @pending_states ["available", "scheduled", "executing", "retryable"]
  # Orphan = executing row attempted by another node, older than 2x the 5m worker timeout.
  @orphan_age_sec 600

  @metrics %{
    funding_rate: %{
      queue: :cryptocompare_funding_rate_historical_jobs_queue,
      pause_resume_queue: :cryptocompare_funding_rate_historical_jobs_pause_resume_queue,
      scheduler: Sanbase.Cryptocompare.FundingRate.HistoricalScheduler,
      cron_type: "schedule_historical_funding_rate_jobs",
      cron_stale_after_sec: 2 * 3600
    },
    open_interest: %{
      queue: :cryptocompare_open_interest_historical_jobs_queue,
      pause_resume_queue: :cryptocompare_open_interest_historical_jobs_pause_resume_queue,
      scheduler: Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler,
      cron_type: "schedule_historical_open_interest_jobs",
      cron_stale_after_sec: 2 * 3600
    },
    price: %{
      queue: :cryptocompare_historical_jobs_queue,
      pause_resume_queue: :cryptocompare_historical_jobs_pause_resume_queue,
      scheduler: Sanbase.Cryptocompare.Price.HistoricalScheduler,
      cron_type: "schedule_historical_price_jobs",
      cron_stale_after_sec: 26 * 3600
    }
  }

  # ======================================================================
  # Overview report
  # ======================================================================

  def report(metrics \\ [:funding_rate, :open_interest])
  def report(:all), do: report(Map.keys(@metrics))
  def report(metric) when is_atom(metric), do: report([metric])

  def report(metrics) when is_list(metrics) do
    with_conf(fn conf ->
      notifier = safe(fn -> Oban.Notifier.status(@conf_name) end, :unknown)
      leader = safe(fn -> Oban.Peer.leader?(@conf_name) end, :unknown)

      isolated_note =
        if notifier == :isolated,
          do: "  <-- !! pg_notify down: pause/resume signals are LOST",
          else: ""

      IO.puts("""

      ==== OBAN SCRAPERS @ #{DateTime.utc_now() |> DateTime.truncate(:second)} ====
      node: #{node()}  oban node: #{conf.node}  prefix: #{inspect(conf.prefix)}
      notifier: #{inspect(notifier)}#{isolated_note}
      leader?: #{inspect(leader)} (Cron/Pruner/Stager run on leader)  connected: #{inspect(Node.list())}
      """)

      Enum.each(metrics, &print_metric(conf, &1))
    end)
  end

  defp print_metric(conf, metric) do
    m = Map.fetch!(@metrics, metric)
    d = collect(conf, m)

    IO.puts("""
    ---- #{String.upcase(to_string(metric))} (#{m.queue}) ----
    producer main : #{fmt_producer(d.main_meta)}
    producer p/r  : #{fmt_producer(d.pr_meta)}
    #{fmt_counts(d)}  last job completed: #{rel(d.last_completed)}
    """)

    if d.executing != [] do
      IO.puts("    executing (oldest first, max 15):")

      Enum.each(d.executing, fn j ->
        mark = if j in d.orphans, do: "  <-- ORPHAN (dead node)", else: ""

        IO.puts(
          "      id=#{j.id} started=#{rel(j.attempted_at)} node=#{Enum.at(j.attempted_by || [], 0)} " <>
            "#{j.args["market"] || "?"}/#{j.args["instrument"] || "?"}#{mark}"
        )
      end)
    end

    IO.puts("    pause/resume queue (last 5):")
    if d.pr_history == [], do: IO.puts("      (empty)")

    Enum.each(d.pr_history, fn j ->
      IO.puts(
        "      id=#{j.id} #{j.args["type"]} #{j.state} scheduled=#{rel(j.scheduled_at)} " <>
          "completed=#{rel(j.completed_at)}"
      )
    end)

    IO.puts("    cron feed (#{m.cron_type}, last 3):")
    if d.cron_jobs == [], do: IO.puts("      none in last 7d")

    Enum.each(d.cron_jobs, fn j ->
      IO.puts("      id=#{j.id} #{j.state} inserted=#{rel(j.inserted_at)}")
    end)

    IO.puts("    VERDICT")
    Enum.each(verdict(metric, m, d), &IO.puts("      * " <> &1))
    IO.puts("")
  end

  defp collect(conf, m) do
    executing = executing_jobs(conf, m.queue)

    %{
      main_meta: producer_meta(m.queue),
      pr_meta: producer_meta(m.pause_resume_queue),
      counts: state_counts(conf, m.queue),
      snoozed: snoozed_info(conf, m.queue),
      executing: executing,
      orphans: Enum.filter(executing, &orphan?(&1, conf.node)),
      pending_resumes: pending_resumes(conf, m.pause_resume_queue),
      pr_history: pr_history(conf, m.pause_resume_queue),
      last_completed: last_completed_at(conf, m.queue),
      cron_jobs: cron_feed(conf, m.cron_type)
    }
  end

  # ======================================================================
  # Verdict — every check returns nil or a message; non-nils are printed.
  # ======================================================================

  defp verdict(metric, m, d) do
    checks = [
      check_producer(metric, d),
      check_pr_producer(d),
      check_orphans(metric, d),
      check_flow(d),
      check_cron(m, d),
      check_heartbeat(d)
    ]

    case Enum.reject(checks, &is_nil/1) do
      [] -> ["Looks healthy."]
      lines -> lines
    end
  end

  defp check_producer(metric, %{main_meta: nil}) do
    "main producer NOT RUNNING on this node — wrong pod, or the queue supervisor crashed" <>
      " (metric: #{metric})"
  end

  defp check_producer(metric, %{main_meta: %{paused: true}, pending_resumes: []}) do
    "PAUSED with NO pending resume -> stuck until manual resume: " <>
      "ObanScrapersDebug.force_resume(:#{metric})"
  end

  defp check_producer(_metric, %{main_meta: %{paused: true}, pending_resumes: [j | _]}) do
    overdue? = DateTime.diff(DateTime.utc_now(), j.scheduled_at, :second) > 60

    if overdue? do
      "PAUSED, resume job id=#{j.id} OVERDUE (due #{rel(j.scheduled_at)}, state=#{j.state}). " <>
        "Suspects: pause_resume producer down/paused, notifier :isolated, stager stuck."
    else
      "PAUSED, rate limited. Resume job id=#{j.id} due #{rel(j.scheduled_at)} — normal flow."
    end
  end

  defp check_producer(_metric, _d), do: nil

  defp check_pr_producer(%{pr_meta: %{paused: true}}),
    do: "!! pause_resume queue PAUSED — resume jobs can never run (paused via Oban.Web?)"

  defp check_pr_producer(%{pr_meta: nil}),
    do: "!! pause_resume producer not running on this node"

  defp check_pr_producer(_d), do: nil

  defp check_orphans(_metric, %{orphans: []}), do: nil

  defp check_orphans(metric, %{orphans: orphans}) do
    week_ago = DateTime.add(DateTime.utc_now(), -7 * 86_400, :second)
    recent = Enum.count(orphans, &(DateTime.compare(&1.attempted_at, week_ago) == :gt))

    unique_note =
      if recent > 0,
        do: " #{recent} are <7d old and BLOCK unique re-inserts of the same market/instrument.",
        else: " All older than the 7d unique window, so they block nothing — just zombie rows."

    "#{length(orphans)} ORPHANED executing job(s) (no Lifeline plugin -> never rescued)." <>
      unique_note <>
      " Fix: ObanScrapersDebug.cancel_orphans(:#{metric}, confirm: true) (or retry_orphans)."
  end

  defp check_flow(%{main_meta: nil}), do: nil
  defp check_flow(%{main_meta: %{paused: true}}), do: nil

  defp check_flow(d) do
    %{count: available, min_sched: oldest_avail} = Map.get(d.counts, "available", empty_row())
    %{count: scheduled, min_sched: next_sched} = Map.get(d.counts, "scheduled", empty_row())
    {snoozed, snoozed_min, _} = d.snoozed
    live = length(d.executing) - length(d.orphans)
    limit = d.main_meta.limit

    cond do
      live >= limit ->
        oldest = List.first(d.executing)

        "SATURATED: all #{limit} slots busy, oldest since #{rel(oldest.attempted_at)}. " <>
          "Persistent saturation = slow/hanging HTTP (worker timeout 5m). Try deep_dive/1."

      available == 0 and live == 0 and snoozed > 0 ->
        "IDLE, all work SNOOZED (rate limited). Next due #{rel(snoozed_min)} — wakes on its own."

      available == 0 and live == 0 and scheduled > 0 ->
        "IDLE: #{scheduled} scheduled, next due #{rel(next_sched)}."

      available == 0 and live == 0 ->
        "EMPTY: no pending jobs. If cron feed below is stale, the hourly scheduler is dead."

      available > 0 and live == 0 and stale?(oldest_avail, 120) ->
        "!! #{available} jobs AVAILABLE but nothing executing — producer not dispatching. " <>
          "Check heartbeat/notifier; deep_dive/1 for the producer process."

      true ->
        nil
    end
  end

  defp check_cron(_m, %{cron_jobs: []}), do: "CRON FEED EMPTY: no #{@add_jobs_worker} in 7d."

  defp check_cron(m, %{cron_jobs: [j | _]}) do
    if stale?(j.inserted_at, m.cron_stale_after_sec) do
      "CRON FEED STALE: last insert #{rel(j.inserted_at)}. Cron runs on the Oban leader — " <>
        "check leader? in the header."
    end
  end

  defp check_heartbeat(%{main_meta: %{updated_at: at}}) do
    if stale?(at, 60) do
      "!! producer heartbeat stale (#{rel(at)}) — producer wedged? Consider a pod restart."
    end
  end

  defp check_heartbeat(_d), do: nil

  # ======================================================================
  # deep_dive — live BEAM processes (read-only)
  # ======================================================================

  @doc """
  What the DB cannot show: stacktraces of the processes executing jobs right
  now (see exactly where a job hangs — HTTP recv, Kafka, DB checkout),
  stager mode (:local = notifier down, polling fallback), sonar/peer state,
  hackney HTTP pool saturation. `busy=false` on a job process means it burned
  ~no reductions over 500ms, i.e. genuinely blocked, not slowly working.
  """
  def deep_dive(metric) do
    %{queue: queue} = Map.fetch!(@metrics, metric)
    IO.puts("\n== DEEP DIVE #{metric} (#{queue}) — this node only ==\n")

    for {label, role, keys} <- [
          {"stager", Oban.Stager, [:mode, :interval, :limit]},
          {"sonar ", Oban.Sonar, [:status, :interval]},
          {"peer  ", Oban.Peer, [:leader?, :interval]}
        ] do
      case get_role_state(role) do
        {:ok, state} -> IO.puts("  #{label}: #{inspect(Map.take(state, keys), limit: 10)}")
        {:error, why} -> IO.puts("  #{label}: unavailable (#{inspect(why)})")
      end
    end

    case producer_pid(queue) do
      nil ->
        IO.puts("\n  producer: NOT FOUND on this node")

      pid ->
        info = Process.info(pid, [:message_queue_len, :status])

        IO.puts(
          "\n  producer #{inspect(pid)} status=#{info[:status]} mailbox=#{info[:message_queue_len]}"
        )
    end

    print_stacktraces(queue)
    print_hackney()
    :ok
  end

  defp print_stacktraces(queue) do
    tasks = foreman_children(queue)
    jobs = running_jobs_by_pid(queue)
    IO.puts("\n  #{length(tasks)} live job process(es):")

    before = Map.new(tasks, &{&1, Process.info(&1, :reductions)})
    if tasks != [], do: Process.sleep(500)

    Enum.each(tasks, fn pid ->
      case Process.info(pid, [:current_stacktrace, :status, :reductions]) do
        nil ->
          IO.puts("    #{inspect(pid)} exited during inspection")

        info ->
          {:reductions, red0} = before[pid] || {:reductions, info[:reductions]}
          busy? = info[:reductions] - red0 > 1_000

          job_desc =
            case jobs[pid] do
              {id, args} -> "job=#{id} #{args["market"] || "?"}/#{args["instrument"] || "?"}"
              nil -> "job=?"
            end

          IO.puts("    #{inspect(pid)} #{job_desc} status=#{info[:status]} busy=#{busy?}")

          info[:current_stacktrace]
          |> Enum.take(6)
          |> Enum.each(fn {mod, fun, arity, loc} ->
            line = if loc[:line], do: ":#{loc[:line]}", else: ""
            IO.puts("        #{inspect(mod)}.#{fun}/#{arity} #{loc[:file]}#{line}")
          end)
      end
    end)
  end

  defp print_hackney() do
    stats = safe(fn -> :hackney_pool.get_stats(:default) end, nil)

    case stats do
      nil ->
        IO.puts("\n  hackney :default pool: no stats")

      stats ->
        IO.puts(
          "\n  hackney :default pool: in_use=#{stats[:in_use_count]} free=#{stats[:free_count]} " <>
            "waiting=#{stats[:queue_count]} max=#{stats[:max]}" <>
            if(stats[:queue_count] > 0, do: "  <-- !! pool exhausted", else: "")
        )
    end
  end

  # ======================================================================
  # watch — is the queue moving right now?
  # ======================================================================

  @doc "Print one status line every 5s for `seconds` (default 30, max 600). Read-only."
  def watch(metric, seconds \\ 30) do
    %{queue: queue} = Map.fetch!(@metrics, metric)
    seconds = min(seconds, 600)
    IO.puts("time     | paused | avail | exec | sched | retry | completed since start")

    with_conf(fn conf ->
      base = completed_count(conf, queue)

      for _ <- 1..max(div(seconds, 5), 1) do
        c = state_counts(conf, queue)
        paused = match?(%{paused: true}, producer_meta(queue))
        done = completed_count(conf, queue) - base
        t = Time.utc_now() |> Time.truncate(:second)

        IO.puts(
          "#{t} | #{String.pad_leading(to_string(paused), 6)} | " <>
            "#{pad_count(c, "available")} | #{pad_count(c, "executing", 4)} | " <>
            "#{pad_count(c, "scheduled")} | #{pad_count(c, "retryable")} | +#{done}"
        )

        Process.sleep(5_000)
      end

      :ok
    end)
  end

  defp pad_count(counts, state, width \\ 5) do
    counts |> Map.get(state, empty_row()) |> Map.get(:count) |> to_string()
    |> String.pad_leading(width)
  end

  # ======================================================================
  # history — hourly throughput vs rate-limit hits
  # ======================================================================

  @doc """
  Per-hour completed jobs and rate-limit hits (inserts into the pause_resume
  queue) for the last `hours`. A gap in completions + a resume insert at the
  same hour = the queue was paused by the rate limiter there.
  """
  def history(metric, hours \\ 24) do
    %{queue: queue, pause_resume_queue: pr_queue} = Map.fetch!(@metrics, metric)

    with_conf(fn conf ->
      completed = per_hour(conf, queue, :completed_at, "completed", hours)
      limited = per_hour(conf, pr_queue, :inserted_at, nil, hours)

      IO.puts("hour (UTC)        | completed | rate-limit hits")

      hours_range(hours)
      |> Enum.each(fn hour ->
        c = Map.get(completed, hour, 0)
        l = Map.get(limited, hour, 0)
        bar = String.duplicate("#", min(40, div(c, 25)))
        lim = if l > 0, do: " #{l} !!", else: ""

        IO.puts("#{hour} | #{String.pad_leading(to_string(c), 9)} |#{lim} #{bar}")
      end)

      :ok
    end)
  end

  defp per_hour(conf, queue, ts_field, state, hours) do
    query =
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue) and field(j, ^ts_field) > ago(^hours, "hour"),
        group_by: fragment("date_trunc('hour', ?)", field(j, ^ts_field)),
        select: {fragment("date_trunc('hour', ?)", field(j, ^ts_field)), count(j.id)}
      )

    query = if state, do: where(query, [j], j.state == ^state), else: query

    Oban.Repo.all(conf, query)
    |> Map.new(fn {hour, count} -> {fmt_hour(hour), count} end)
  end

  defp hours_range(hours) do
    now = DateTime.utc_now()
    for h <- hours..0//-1, do: fmt_hour(DateTime.add(now, -h * 3600, :second))
  end

  defp fmt_hour(%{year: y, month: mo, day: d, hour: h}) do
    :io_lib.format("~4..0B-~2..0B-~2..0B ~2..0B:00", [y, mo, d, h]) |> to_string()
  end

  # ======================================================================
  # errors — what is actually failing
  # ======================================================================

  @doc "Tally the last error message of the most recent `limit` failed jobs."
  def errors(metric, limit \\ 200) do
    %{queue: queue} = Map.fetch!(@metrics, metric)

    with_conf(fn conf ->
      rows =
        Oban.Repo.all(
          conf,
          from(j in Oban.Job,
            where: j.queue == ^to_string(queue) and fragment("cardinality(?) > 0", j.errors),
            order_by: [desc: j.id],
            limit: ^limit,
            select: %{state: j.state, errors: j.errors}
          )
        )

      IO.puts("#{length(rows)} recent jobs with errors. Last-error tally:")

      rows
      |> Enum.map(fn j ->
        msg =
          case List.last(j.errors || []) do
            %{"error" => err} -> err |> String.split("\n") |> hd() |> String.slice(0, 90)
            other -> inspect(other) |> String.slice(0, 90)
          end

        {msg, j.state}
      end)
      |> Enum.frequencies()
      |> Enum.sort_by(fn {_k, count} -> -count end)
      |> Enum.take(15)
      |> Enum.each(fn {{msg, state}, count} ->
        IO.puts("  #{String.pad_leading(to_string(count), 5)}x [#{state}] #{msg}")
      end)

      :ok
    end)
  end

  # ======================================================================
  # lag — which instruments stopped progressing (exporter progress table)
  # ======================================================================

  @doc """
  The `n` instruments whose newest exported data point (max_timestamp) is the
  oldest — i.e. the ones falling behind. Uses cryptocompare_exporter_progress
  via Sanbase.Repo (regular table, no oban prefix).
  """
  def lag(metric, n \\ 15) do
    %{queue: queue} = Map.fetch!(@metrics, metric)

    rows =
      Sanbase.Repo.all(
        from(e in Sanbase.Cryptocompare.ExporterProgress,
          where: e.queue == ^to_string(queue),
          order_by: [asc: e.max_timestamp],
          limit: ^n,
          select: {e.key, e.max_timestamp, e.updated_at}
        )
      )

    total =
      Sanbase.Repo.one(
        from(e in Sanbase.Cryptocompare.ExporterProgress,
          where: e.queue == ^to_string(queue),
          select: count(e.id)
        )
      )

    IO.puts("#{total} tracked instruments. #{n} furthest behind (newest data point):")

    Enum.each(rows, fn {key, max_ts, updated_at} ->
      newest = DateTime.from_unix!(max_ts)
      IO.puts("  #{String.pad_trailing(key, 45)} data up to #{newest} (row updated #{rel(updated_at)})")
    end)

    :ok
  end

  # ======================================================================
  # Single job + process listing
  # ======================================================================

  @doc "Dump one oban job row."
  def job(id) do
    with_conf(fn conf ->
      Oban.Repo.one(conf, from(j in Oban.Job, where: j.id == ^id))
      |> IO.inspect(pretty: true, limit: :infinity)

      :ok
    end)
  end

  @doc "Every process Oban registered for this instance + mailbox/status."
  def processes() do
    entries =
      Registry.select(Oban.Registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
      |> Enum.filter(fn {key, _pid} ->
        key == @conf_name or (is_tuple(key) and elem(key, 0) == @conf_name)
      end)
      |> Enum.sort_by(fn {key, _} -> inspect(key) end)

    IO.puts("#{length(entries)} processes for #{inspect(@conf_name)}:")

    Enum.each(entries, fn {key, pid} ->
      role = if is_tuple(key), do: elem(key, 1), else: :supervisor

      case Process.info(pid, [:message_queue_len, :status, :memory]) do
        nil ->
          IO.puts("  #{inspect(role)} #{inspect(pid)} DEAD")

        info ->
          mark = if info[:message_queue_len] > 100, do: "  <-- !! mailbox backing up", else: ""

          IO.puts(
            "  #{String.pad_trailing(inspect(role), 60)} status=#{info[:status]} " <>
              "mailbox=#{info[:message_queue_len]} mem=#{div(info[:memory], 1024)}KiB#{mark}"
          )
      end
    end)

    :ok
  end

  # ======================================================================
  # Mutating helpers — explicit only
  # ======================================================================

  @doc "Resume the main queue, then verify the producer actually unpaused."
  def force_resume(metric) do
    %{queue: queue, scheduler: scheduler} = Map.fetch!(@metrics, metric)
    IO.puts("#{inspect(scheduler)}.resume() -> #{inspect(scheduler.resume())}")
    Process.sleep(1_000)

    case producer_meta(queue) do
      %{paused: false} ->
        IO.puts("OK — producer unpaused")

      %{paused: true} ->
        IO.puts("""
        !! STILL paused. Resume travels over the notifier (pg_notify) — if
           Oban.Notifier.status(#{inspect(@conf_name)}) is :isolated the signal was lost;
           a pod restart re-establishes the LISTEN connection (queue starts paused
           and the scheduler resumes it on boot when the env flag is enabled).
        """)

      nil ->
        IO.puts("!! no local producer — wrong pod?")
    end
  end

  @doc "List orphaned executing rows (attempted by another node, older than #{@orphan_age_sec}s)."
  def orphans(metric) do
    %{queue: queue} = Map.fetch!(@metrics, metric)

    with_conf(fn conf ->
      list = Oban.Repo.all(conf, orphans_query(conf, queue))
      IO.puts("#{length(list)} orphan(s) on #{queue}:")

      Enum.each(list, fn j ->
        IO.puts(
          "  id=#{j.id} started=#{rel(j.attempted_at)} node=#{Enum.at(j.attempted_by, 0)} " <>
            "#{j.args["market"] || "?"}/#{j.args["instrument"] || "?"}"
        )
      end)

      list
    end)
  end

  @doc """
  Cancel orphaned executing rows (-> cancelled, pruned by Pruner after 7d).
  Right choice for ancient orphans: the work is stale, don't re-run it.
  Dry run unless `confirm: true`. Verify the node is truly dead first
  (`Node.list()` in the report header / kubectl) — the query only excludes
  THIS node, not other live scraper pods.
  """
  def cancel_orphans(metric, opts \\ []) do
    act_on_orphans(metric, opts, fn _conf, query ->
      Oban.cancel_all_jobs(@conf_name, query)
    end)
  end

  @doc """
  Move orphaned executing rows back to available so they re-run. Right choice
  for RECENT orphans (a deploy killed a pod mid-job and the work still
  matters). Careful with ancient ones: jobs with schedule_next_job=true will
  restart historical backfill chains and eat the rate limit.
  Dry run unless `confirm: true`.
  """
  def retry_orphans(metric, opts \\ []) do
    act_on_orphans(metric, opts, fn conf, query ->
      Oban.Repo.update_all(conf, query, set: [state: "available"])
    end)
  end

  defp act_on_orphans(metric, opts, fun) do
    list = orphans(metric)
    %{queue: queue} = Map.fetch!(@metrics, metric)

    cond do
      list == [] ->
        :ok

      Keyword.get(opts, :confirm, false) ->
        with_conf(fn conf ->
          ids = Enum.map(list, & &1.id)
          query = from(j in Oban.Job, where: j.id in ^ids and j.state == "executing")

          n =
            case fun.(conf, query) do
              {:ok, n} when is_integer(n) -> n
              {n, _} when is_integer(n) -> n
            end

          IO.puts("Affected #{n} job(s) on #{queue}.")
        end)

      true ->
        IO.puts("Dry run. Re-run with `confirm: true` to apply.")
    end
  end

  defp orphans_query(conf, queue) do
    cutoff = DateTime.add(DateTime.utc_now(), -@orphan_age_sec, :second)

    running_ids =
      case producer_meta(queue) do
        %{running: ids} -> ids
        _ -> []
      end

    from(j in Oban.Job,
      where:
        j.queue == ^to_string(queue) and j.state == "executing" and
          j.attempted_at < ^cutoff and
          fragment("?[1] != ?", j.attempted_by, ^conf.node) and
          j.id not in ^running_ids,
      order_by: [asc: j.attempted_at],
      select: %{id: j.id, attempted_at: j.attempted_at, attempted_by: j.attempted_by, args: j.args}
    )
  end

  # ======================================================================
  # Data fetchers (read-only)
  # ======================================================================

  defp with_conf(fun) do
    case safe(fn -> Oban.config(@conf_name) end, nil) do
      nil ->
        IO.puts("!! #{inspect(@conf_name)} not running on this node — attach to the scrapers pod.")

      conf ->
        fun.(conf)
    end
  end

  defp producer_meta(queue), do: safe(fn -> Oban.check_queue(@conf_name, queue: queue) end, nil)

  defp state_counts(conf, queue) do
    Oban.Repo.all(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue),
        group_by: j.state,
        select: {j.state, %{count: count(j.id), min_sched: min(j.scheduled_at)}}
      )
    )
    |> Map.new()
  end

  # Snoozed = scheduled with attempt > 0: ran at least once, put back by the
  # rate limiter's {:snooze, seconds}.
  defp snoozed_info(conf, queue) do
    Oban.Repo.one(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue) and j.state == "scheduled" and j.attempt > 0,
        select: {count(j.id), min(j.scheduled_at), max(j.scheduled_at)}
      )
    ) || {0, nil, nil}
  end

  defp executing_jobs(conf, queue) do
    Oban.Repo.all(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue) and j.state == "executing",
        order_by: [asc: j.attempted_at],
        limit: 15,
        select: %{id: j.id, attempted_at: j.attempted_at, attempted_by: j.attempted_by, args: j.args}
      )
    )
  end

  defp orphan?(job, conf_node) do
    Enum.at(job.attempted_by || [], 0) != conf_node and stale?(job.attempted_at, @orphan_age_sec)
  end

  defp pending_resumes(conf, pr_queue) do
    Oban.Repo.all(
      conf,
      from(j in Oban.Job,
        where:
          j.queue == ^to_string(pr_queue) and j.state in ^@pending_states and
            fragment("?->>'type' = 'resume'", j.args),
        order_by: [asc: j.scheduled_at],
        limit: 5,
        select: %{id: j.id, state: j.state, scheduled_at: j.scheduled_at}
      )
    )
  end

  defp pr_history(conf, pr_queue) do
    Oban.Repo.all(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(pr_queue),
        order_by: [desc: j.id],
        limit: 5,
        select: %{id: j.id, state: j.state, args: j.args, scheduled_at: j.scheduled_at, completed_at: j.completed_at}
      )
    )
  end

  defp last_completed_at(conf, queue) do
    Oban.Repo.one(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue) and j.state == "completed",
        order_by: [desc: j.id],
        limit: 1,
        select: j.completed_at
      )
    )
  end

  defp completed_count(conf, queue) do
    Oban.Repo.one(
      conf,
      from(j in Oban.Job,
        where: j.queue == ^to_string(queue) and j.state == "completed",
        select: count(j.id)
      )
    )
  end

  defp cron_feed(conf, cron_type) do
    Oban.Repo.all(
      conf,
      from(j in Oban.Job,
        where: j.worker == ^@add_jobs_worker and fragment("?->>'type' = ?", j.args, ^cron_type),
        order_by: [desc: j.id],
        limit: 3,
        select: %{id: j.id, state: j.state, inserted_at: j.inserted_at}
      )
    )
  end

  # ======================================================================
  # BEAM process helpers
  # ======================================================================

  defp whereis_role(role), do: safe(fn -> Oban.Registry.whereis(@conf_name, role) end, nil)

  defp producer_pid(queue),
    do: whereis_role({:producer, to_string(queue)}) || whereis_role({:producer, queue})

  defp foreman_children(queue) do
    case whereis_role({:foreman, to_string(queue)}) || whereis_role({:foreman, queue}) do
      nil -> []
      pid -> safe(fn -> Task.Supervisor.children(pid) end, [])
    end
  end

  defp get_role_state(role) do
    case whereis_role(role) do
      nil -> {:error, :not_found}
      pid -> safe_get_state(pid)
    end
  end

  # Best effort: the producer's running map shape is an internal detail.
  defp running_jobs_by_pid(queue) do
    with pid when is_pid(pid) <- producer_pid(queue),
         {:ok, state} <- safe_get_state(pid) do
      (Map.get(state, :running) || %{})
      |> Enum.reduce(%{}, fn
        {_ref, {pid, %{job: %{id: id, args: args}}}}, acc -> Map.put(acc, pid, {id, args})
        _, acc -> acc
      end)
    else
      _ -> %{}
    end
  end

  defp safe_get_state(pid) do
    {:ok, :sys.get_state(pid, 2_000) |> to_plain_map()}
  rescue
    error -> {:error, error}
  catch
    :exit, reason -> {:error, reason}
  end

  defp to_plain_map(%_{} = struct), do: Map.from_struct(struct)
  defp to_plain_map(map) when is_map(map), do: map
  defp to_plain_map(other), do: %{value: other}

  defp safe(fun, default) do
    fun.()
  rescue
    _ -> default
  catch
    :exit, _ -> default
  end

  # ======================================================================
  # Formatting
  # ======================================================================

  defp fmt_producer(nil), do: "NOT RUNNING on this node"

  defp fmt_producer(meta) do
    "paused=#{meta.paused} limit=#{meta.limit} executing_now=#{length(meta.running)} " <>
      "heartbeat=#{rel(meta.updated_at)}"
  end

  defp fmt_counts(d) do
    {snoozed, snoozed_min, _} = d.snoozed

    line =
      ~w[available executing scheduled retryable completed cancelled discarded]
      |> Enum.map(fn state ->
        "#{state}=#{Map.get(d.counts, state, empty_row()).count}"
      end)
      |> Enum.join(" ")

    extras =
      [
        avail_extra(d.counts["available"]),
        sched_extra(d.counts["scheduled"]),
        if(snoozed > 0, do: "snoozed=#{snoozed} next due #{rel(snoozed_min)}")
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join("; ")

    "    counts: #{line}" <> if(extras == "", do: "", else: "\n    #{extras}")
  end

  defp avail_extra(%{count: c, min_sched: min_s}) when c > 0, do: "oldest available #{rel(min_s)}"
  defp avail_extra(_), do: nil

  defp sched_extra(%{count: c, min_sched: min_s}) when c > 0, do: "next scheduled #{rel(min_s)}"
  defp sched_extra(_), do: nil

  defp empty_row(), do: %{count: 0, min_sched: nil}

  defp stale?(nil, _sec), do: false
  defp stale?(dt, sec), do: DateTime.diff(DateTime.utc_now(), to_dt(dt), :second) > sec

  defp rel(nil), do: "n/a"

  defp rel(dt) do
    diff = DateTime.diff(DateTime.utc_now(), to_dt(dt), :second)
    if diff >= 0, do: "#{dur(diff)} ago", else: "in #{dur(-diff)}"
  end

  defp to_dt(%DateTime{} = dt), do: dt
  defp to_dt(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp dur(s) when s < 60, do: "#{s}s"
  defp dur(s) when s < 3600, do: "#{div(s, 60)}m #{rem(s, 60)}s"
  defp dur(s) when s < 86_400, do: "#{div(s, 3600)}h #{rem(s, 3600) |> div(60)}m"
  defp dur(s), do: "#{div(s, 86_400)}d #{rem(s, 86_400) |> div(3600)}h"
end

IO.puts("""
ObanScrapersDebug loaded.

Read-only : report/0,1  deep_dive/1  watch/1,2  history/1,2  errors/1,2
            lag/1,2  orphans/1  job/1  processes/0
Mutating  : force_resume/1  cancel_orphans/2  retry_orphans/2  (need confirm: true)
""")
