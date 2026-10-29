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

  Only one scheduler should run. A second one would fetch the same days, but
  cannot break a rescrape, as the cursor is moved with conditional updates.
  """
  use GenServer

  alias Sanbase.Model.LatestCoinmarketcapData
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

  @impl true
  def init(opts) do
    enabled? =
      Keyword.get_lazy(opts, :enabled?, fn ->
        Config.module_get(Coinmarketcap, :sync_enabled, false) in [true, "true"]
      end)

    if enabled? do
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
      state
      |> reload_rescrapes()
      |> fill_slots()

    {:noreply, state}
  end

  def handle_info({ref, result}, state) when is_map_key(state.tasks, ref) do
    Process.demonitor(ref, [:flush])
    {id, tasks} = Map.pop(state.tasks, ref)

    state =
      %{state | tasks: tasks}
      |> handle_result(id, ref, result)
      |> fill_slots()

    {:noreply, state}
  end

  def handle_info({:DOWN, ref, :process, _pid, reason}, state)
      when is_map_key(state.tasks, ref) do
    {id, tasks} = Map.pop(state.tasks, ref)

    state =
      %{state | tasks: tasks}
      |> handle_result(id, ref, {:error, "Fetching prices exited: #{inspect(reason)}"})
      |> fill_slots()

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  # Private functions

  defp reload_rescrapes(state) do
    rescrapes =
      Enum.reduce(ScheduleRescrapePrice.list_active(), %{}, fn srp, acc ->
        case reloaded_entry(state, srp) do
          {:ok, entry} -> Map.put(acc, srp.id, entry)
          :error -> acc
        end
      end)

    # The rescrapes that are no longer active are dropped. The results of their
    # days in flight are ignored.
    %{state | rescrapes: rescrapes}
  end

  # Keep the in-memory cursor, only the priority can be changed from outside
  defp reloaded_entry(state, srp) do
    case Map.fetch(state.rescrapes, srp.id) do
      {:ok, entry} -> {:ok, %{entry | srp: %{entry.srp | priority: srp.priority}}}
      :error -> new_entry(srp)
    end
  end

  defp new_entry(srp) do
    case LatestCoinmarketcapData.coinmarketcap_integer_id(srp.project) do
      nil ->
        error = "#{Sanbase.Project.describe(srp.project)} has no coinmarketcap integer id"
        _ = ScheduleRescrapePrice.mark_failed(srp, error)
        :error

      cmc_integer_id ->
        {:ok,
         %{
           srp: srp,
           cmc_integer_id: cmc_integer_id,
           # The start of the next day to fetch
           next_from: srp |> ScheduleRescrapePrice.cursor() |> to_unix(),
           # The days in flight, in the order they were started: {task_ref, interval, done?}
           in_flight: [],
           failures: 0,
           retry_at: nil
         }}
    end
  end

  defp fill_slots(state) do
    state = finish_completed(state)

    with true <- map_size(state.tasks) < state.max_concurrency,
         %{} = entry <- next_entry(state) do
      state
      |> start_next_day(entry)
      |> fill_slots()
    else
      _ ->
        maybe_notify_idle(state)
        state
    end
  end

  defp finish_completed(state) do
    completed =
      for {id, %{in_flight: []} = entry} <- state.rescrapes,
          entry.next_from >= end_unix(entry.srp),
          do: id

    Enum.reduce(completed, state, fn id, state ->
      srp = state.rescrapes[id].srp
      Logger.info("[CMC Rescrape] Finished rescrape #{srp.id} for #{srp.project.slug}")
      _ = ScheduleRescrapePrice.mark_finished(srp)
      drop_rescrape(state, id)
    end)
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
