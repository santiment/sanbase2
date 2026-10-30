defmodule Sanbase.ExternalServices.Coinmarketcap.RescrapeScheduler do
  @moduledoc ~s"""
  Executes the `ScheduleRescrapePrice` rescrapes.

  The database row is the source of truth for a rescrape. The scheduler moves
  the rescrape's own cursor (`progress_datetime`) and never touches the
  progress of the regular scraper. Every few seconds the active rescrapes are
  reloaded, so new rescrapes, priority changes and cancellations are picked up.

  The rescrapes are fetched day by day. Whenever a request slot is free, the
  next day of the rescrape with the highest priority is fetched (the oldest
  rescrape first among equal priorities). Up to 2 days of a rescrape are
  fetched in parallel, so a :high priority rescrape always has a request
  waiting in the rate limiter while the previous response is processed. The
  cursor moves only over contiguous fetched days.

  A failed day is retried from the cursor after a minute. After 20 consecutive
  failures the rescrape is marked as failed. A restart loses only the days
  that were in flight, the running rescrapes continue from their cursor.

  The scheduler is isolated from the other scrapers, see `isolated_child_spec/1`.
  Errors while working on a rescrape (e.g. the DB is unavailable) are logged and
  do not crash the scheduler. The rescrape is dropped from memory and reloaded
  from its cursor on the next refresh. A rescrape whose `from` is in the future
  waits until then.

  Only one scheduler should run. A second one would fetch the same days, but
  cannot break a rescrape, as the cursor is moved with conditional updates.
  """
  use GenServer

  alias Sanbase.ExternalServices.Coinmarketcap
  alias Sanbase.ExternalServices.Coinmarketcap.{ScheduleRescrapePrice, WebApi}
  alias Sanbase.Utils.Config

  require Logger

  @refresh_interval_ms 5_000
  @max_concurrency 4
  @max_concurrency_per_rescrape 2
  @max_failures 20
  @retry_after_ms 60_000
  @interval_seconds 86_400
  # WebApi skips intervals shorter than 1 hour
  @min_interval_seconds 3600
  @supervisor_max_restarts 3
  @supervisor_max_seconds 60

  # The scheduler applies its own changes to the in-memory rescrape too, so a
  # difference in these fields means the rescrape was changed from outside,
  # e.g. cancelled and resumed between two refreshes
  @externally_changed_fields [:status, :from, :to, :progress_datetime, :last_error]

  @doc ~s"""
  Options (all but :enabled? are meant for tests):
    - :enabled? - by default it runs when the coinmarketcap scraper is enabled
    - :name, :refresh_interval_ms, :max_concurrency, :max_failures, :retry_after_ms
    - :notify - a pid that gets `{:rescrape_scheduler, :idle}` every time there
      is nothing to fetch and no request in flight
  """
  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc ~s"""
  The child spec used by the scrapers supervisor. It keeps a crash loop of the
  scheduler away from the other scrapers.

  The scheduler runs under its own supervisor, which gives up after
  #{@supervisor_max_restarts} restarts in #{@supervisor_max_seconds} seconds. That
  supervisor is :temporary, so its parent neither restarts it nor counts its
  exit towards its own restart limit. When it gives up, only the rescrapes stop,
  until the next restart of the app.
  """
  def isolated_child_spec(opts \\ []) do
    supervisor_opts = [
      strategy: :one_for_one,
      max_restarts: @supervisor_max_restarts,
      max_seconds: @supervisor_max_seconds
    ]

    %{
      id: :cmc_rescrape_scheduler_supervisor,
      start: {Supervisor, :start_link, [[{__MODULE__, opts}], supervisor_opts]},
      type: :supervisor,
      restart: :temporary
    }
  end

  @impl true
  def init(opts) do
    if enabled?(opts) do
      send(self(), :refresh)

      {:ok,
       %{
         # rescrape id => entry, see new_entry/2
         rescrapes: %{},
         # task ref => rescrape id
         tasks: %{},
         refresh_interval_ms: Keyword.get(opts, :refresh_interval_ms, @refresh_interval_ms),
         max_concurrency: Keyword.get(opts, :max_concurrency, @max_concurrency),
         max_failures: Keyword.get(opts, :max_failures, @max_failures),
         retry_after_ms: Keyword.get(opts, :retry_after_ms, @retry_after_ms),
         notify: Keyword.get(opts, :notify)
       }}
    else
      :ignore
    end
  end

  @impl true
  def handle_info(:refresh, state) do
    Process.send_after(self(), :refresh, state.refresh_interval_ms)

    state =
      safely(fn -> reload_rescrapes(state) end, state, "Reloading the rescrapes")
      |> fill_slots()

    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_map_key(state.tasks, ref) do
    Process.demonitor(ref, [:flush])
    {:noreply, task_done(state, ref, result)}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.tasks, ref) do
    {:noreply, task_done(state, ref, {:error, "Fetching prices exited: #{inspect(reason)}"})}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions

  # Reading the config must not crash, as a failed start would stop the
  # scrapers supervisor from starting
  defp enabled?(opts) do
    Keyword.get_lazy(opts, :enabled?, fn ->
      Config.module_get(Coinmarketcap, :sync_enabled, false) in [true, "true"]
    end)
  catch
    kind, reason ->
      Logger.error(
        "[CMC Rescrape] The scheduler is disabled, reading its config failed: " <>
          Exception.format(kind, reason, __STACKTRACE__)
      )

      false
  end

  defp task_done(state, ref, result) do
    {id, tasks} = Map.pop(state.tasks, ref)
    state = %{state | tasks: tasks}

    safely(
      fn -> handle_result(state, id, ref, result) end,
      drop_rescrape(state, id),
      "Handling a result of rescrape #{id}"
    )
    |> fill_slots()
  end

  defp reload_rescrapes(state) do
    {known, new} =
      ScheduleRescrapePrice.list_active()
      |> Enum.split_with(&Map.has_key?(state.rescrapes, &1.id))

    known = Map.new(known, &{&1.id, reloaded_entry(state.rescrapes[&1.id], &1)})

    # The rescrapes that are no longer active are dropped. The results of their
    # days in flight are ignored.
    %{state | rescrapes: Map.merge(known, new_entries(new))}
  end

  # Keep the in-memory cursor, only the priority can be changed from outside.
  # A rescrape changed in another way is restarted from its cursor in the DB.
  defp reloaded_entry(entry, srp) do
    if Map.take(entry.srp, @externally_changed_fields) ==
         Map.take(srp, @externally_changed_fields),
       do: %{entry | srp: %{entry.srp | priority: srp.priority}},
       else: new_entry(%{srp | project: entry.srp.project}, entry.cmc_integer_id)
  end

  defp new_entries([]), do: %{}

  defp new_entries(srps) do
    srps = Sanbase.Repo.preload(srps, :project)
    cmc_ids = ScheduleRescrapePrice.coinmarketcap_integer_ids(Enum.map(srps, & &1.project_id))

    Enum.reduce(srps, %{}, fn srp, acc ->
      case Map.fetch(cmc_ids, srp.project_id) do
        {:ok, cmc_integer_id} ->
          Map.put(acc, srp.id, new_entry(srp, cmc_integer_id))

        :error ->
          error = "#{Sanbase.Project.describe(srp.project)} has no coinmarketcap integer id"

          safely(
            fn -> ScheduleRescrapePrice.mark_failed(srp, error) end,
            :error,
            "Failing rescrape #{srp.id}"
          )

          acc
      end
    end)
  end

  defp new_entry(srp, cmc_integer_id) do
    %{
      srp: srp,
      cmc_integer_id: cmc_integer_id,
      # The start of the next day to fetch
      next_from: srp |> ScheduleRescrapePrice.cursor() |> to_unix(),
      # The days in flight, in the order they were started: {task_ref, interval, done?}
      in_flight: [],
      failures: 0,
      retry_at: nil
    }
  end

  defp fill_slots(state) do
    state = finish_completed(state)

    with true <- map_size(state.tasks) < state.max_concurrency,
         %{srp: %{id: id}} = entry <- next_entry(state) do
      safely(
        fn -> start_next_day(state, entry) end,
        drop_rescrape(state, id),
        "Starting a day of rescrape #{id}"
      )
      |> fill_slots()
    else
      _ ->
        maybe_notify_idle(state)
        state
    end
  end

  defp finish_completed(state) do
    completed =
      for {id, %{in_flight: []} = entry} <- state.rescrapes, finished?(entry), do: id

    Enum.reduce(completed, state, fn id, state ->
      srp = state.rescrapes[id].srp
      Logger.info("[CMC Rescrape] Finished rescrape #{srp.id} for #{srp.project.slug}")

      safely(
        fn -> ScheduleRescrapePrice.mark_finished(srp) end,
        :error,
        "Finishing rescrape #{srp.id}"
      )

      drop_rescrape(state, id)
    end)
  end

  # A rescrape whose `from` is in the future has not started, so it is not finished
  defp finished?(%{srp: srp, next_from: next_from}) do
    next_from >= end_unix(srp) and to_unix(srp.from) <= DateTime.to_unix(DateTime.utc_now())
  end

  # The rescrape with the highest priority that has a day to fetch
  defp next_entry(state) do
    now = System.monotonic_time(:millisecond)

    state.rescrapes
    |> Map.values()
    |> Enum.filter(fn entry ->
      length(entry.in_flight) < @max_concurrency_per_rescrape and
        entry.next_from < end_unix(entry.srp) and
        (entry.retry_at == nil or entry.retry_at <= now)
    end)
    |> Enum.min_by(&{ScheduleRescrapePrice.priority_rank(&1.srp), &1.srp.id}, fn -> nil end)
  end

  defp start_next_day(state, %{srp: %{status: :pending} = srp} = entry) do
    case ScheduleRescrapePrice.mark_running(srp) do
      {:ok, srp} -> start_next_day(state, %{entry | srp: srp})
      # Cancelled in the meantime
      {:error, :not_active} -> drop_rescrape(state, srp.id)
    end
  end

  defp start_next_day(state, entry) do
    %{srp: srp, cmc_integer_id: cmc_integer_id, next_from: from} = entry
    interval = interval(from, end_unix(srp))

    task =
      Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
        fetch_and_export(srp.project, cmc_integer_id, interval, priority: srp.priority)
      end)

    entry = %{
      entry
      | next_from: from + @interval_seconds,
        in_flight: entry.in_flight ++ [{task.ref, interval, false}]
    }

    %{
      state
      | rescrapes: Map.put(state.rescrapes, srp.id, entry),
        tasks: Map.put(state.tasks, task.ref, srp.id)
    }
  end

  defp handle_result(state, id, ref, result) do
    with %{} = entry <- state.rescrapes[id],
         true <- List.keymember?(entry.in_flight, ref, 0) do
      case result do
        {:ok, _interval} -> day_fetched(state, entry, ref)
        {:error, error} -> day_failed(state, entry, error)
      end
    else
      # The rescrape is no longer active or the day was dropped after an error
      _ -> state
    end
  end

  defp day_fetched(state, entry, ref) do
    in_flight =
      Enum.map(entry.in_flight, fn
        {^ref, interval, _done?} -> {ref, interval, true}
        day -> day
      end)

    {fetched, in_flight} = Enum.split_while(in_flight, fn {_ref, _interval, done?} -> done? end)

    case List.last(fetched) do
      # An earlier day is still in flight
      nil ->
        put_entry(state, %{entry | in_flight: in_flight})

      {_ref, {_from, to}, true} ->
        case ScheduleRescrapePrice.advance_cursor(entry.srp, from_unix(to)) do
          {:ok, srp} -> put_entry(state, %{entry | srp: srp, in_flight: in_flight, failures: 0})
          # Cancelled, or the cursor was moved by someone else
          {:error, :not_active} -> drop_rescrape(state, entry.srp.id)
        end
    end
  end

  defp day_failed(state, %{srp: srp} = entry, error) do
    failures = entry.failures + 1

    Logger.warning(
      "[CMC Rescrape] Rescrape #{srp.id} for #{srp.project.slug} failed " <>
        "(#{failures}/#{state.max_failures}): #{error}"
    )

    if failures >= state.max_failures do
      _ = ScheduleRescrapePrice.mark_failed(srp, error)
      drop_rescrape(state, srp.id)
    else
      case ScheduleRescrapePrice.store_error(srp, error) do
        {:ok, srp} ->
          # Fetch again from the cursor. The results of the other days in flight are ignored.
          put_entry(state, %{
            entry
            | srp: srp,
              failures: failures,
              in_flight: [],
              next_from: srp |> ScheduleRescrapePrice.cursor() |> to_unix(),
              retry_at: System.monotonic_time(:millisecond) + state.retry_after_ms
          })

        {:error, :not_active} ->
          drop_rescrape(state, srp.id)
      end
    end
  end

  defp fetch_and_export(project, cmc_integer_id, interval, opts) do
    with {:ok, price_points} <- WebApi.fetch_price_points(cmc_integer_id, interval, opts),
         {:export, :ok} <- {:export, WebApi.export_price_points(project, price_points)} do
      {:ok, interval}
    else
      {:export, error} -> {:error, "Kafka export failed: #{inspect(error)}"}
      {:error, error} -> {:error, error}
    end
  end

  # Runs `fun` and returns `fallback` if it raises or exits, so a failure (e.g.
  # the DB is unavailable) does not crash the scheduler. A rescrape dropped
  # from memory is reloaded from its cursor on the next refresh.
  defp safely(fun, fallback, action) do
    fun.()
  catch
    kind, reason ->
      Logger.error(
        "[CMC Rescrape] #{action} failed: " <> Exception.format(kind, reason, __STACKTRACE__)
      )

      fallback
  end

  defp put_entry(state, entry),
    do: %{state | rescrapes: Map.put(state.rescrapes, entry.srp.id, entry)}

  defp drop_rescrape(state, id), do: %{state | rescrapes: Map.delete(state.rescrapes, id)}

  defp maybe_notify_idle(%{notify: pid, tasks: tasks}) when is_pid(pid) and map_size(tasks) == 0,
    do: send(pid, {:rescrape_scheduler, :idle})

  defp maybe_notify_idle(_state), do: :ok

  # Scrape until `to`, but not in the future
  defp end_unix(srp) do
    min(to_unix(srp.to), DateTime.utc_now() |> DateTime.to_unix())
  end

  # A day starting at `from`. A too short last interval is extended backwards.
  # Exporting the overlapping points again is harmless, the regular scraper
  # does the same.
  defp interval(from, end_unix) do
    to = min(from + @interval_seconds, end_unix)
    {min(from, to - @min_interval_seconds), to}
  end

  defp to_unix(%NaiveDateTime{} = ndt),
    do: ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()

  defp from_unix(unix), do: unix |> DateTime.from_unix!() |> DateTime.to_naive()
end
