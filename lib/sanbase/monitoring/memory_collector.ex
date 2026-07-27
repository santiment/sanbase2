defmodule Sanbase.Monitoring.MemoryCollector do
  @moduledoc """
  Records one `Sanbase.Monitoring.MemoryStat` row per minute for this pod.

  Runs on every container type — each pod reports itself, there is no
  cross-pod coordination. Only cheap, side-effect-free stats are collected
  (see `Sanbase.Monitoring.MemorySnapshot`); nothing here forces GC or walks
  per-process binary refs. The O(process count) process-groups breakdown is
  collected only on every 5th sample.

  Each sample runs in a short-lived `Task` so whatever garbage the sampling
  itself produces dies with the task process instead of accumulating in this
  GenServer's heap. Old rows are pruned hourly (`:retention_days`, default 90);
  the delete is idempotent so all pods can run it concurrently.

  Toggled with the `MEMORY_COLLECTOR_ENABLED` env var (default enabled);
  retention is overridable with `MEMORY_COLLECTOR_RETENTION_DAYS`.
  """

  use GenServer

  alias Sanbase.Monitoring.MemorySnapshot
  alias Sanbase.Monitoring.MemoryStat
  alias Sanbase.Utils.Config

  require Logger

  @default_interval :timer.minutes(1)
  @default_retention_days 90
  # collect process groups on every Nth sample; prune once per 60 samples
  @process_groups_every_nth 5
  @prune_every_nth 60

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Keyword.get(opts, :name, __MODULE__))
  end

  @doc """
  Whether this pod should collect samples. Enabled unless
  `MEMORY_COLLECTOR_ENABLED` says otherwise; an unrecognized value keeps
  collection on rather than silently turning off fleet-wide monitoring.
  """
  def enabled?() do
    value = Config.module_get(__MODULE__, :enabled, true)

    case Config.parse_boolean_value(value) do
      nil ->
        Logger.warning(
          "[MemoryCollector] unrecognized MEMORY_COLLECTOR_ENABLED value #{inspect(value)}, " <>
            "expected one of true/false/1/0 — staying enabled"
        )

        true

      boolean ->
        boolean
    end
  end

  @impl GenServer
  def init(opts) do
    state = %{
      interval: Keyword.get(opts, :interval, @default_interval),
      retention_days: Keyword.get(opts, :retention_days) || retention_days_from_config(),
      pod_name: pod_name(),
      container_type: Sanbase.ApplicationUtils.container_type(),
      beam_started_at: MemorySnapshot.beam_started_at(),
      tick: 0
    }

    schedule(state.interval)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:sample, state) do
    state = %{state | tick: state.tick + 1}

    in_task(fn -> sample(state, collect_process_groups?(state.tick)) end)

    if prune_due?(state.tick) do
      in_task(fn -> prune(state) end)
    end

    schedule(state.interval)
    {:noreply, state}
  end

  @doc false
  def collect_process_groups?(tick), do: rem(tick, @process_groups_every_nth) == 1

  @doc false
  def prune_due?(tick), do: rem(tick, @prune_every_nth) == 0

  # Public only for tests — the collector itself always calls this in a Task.
  @doc false
  def sample(state, include_process_groups) do
    snapshot = MemorySnapshot.collect(include_process_groups: include_process_groups)

    details =
      case snapshot.process_groups do
        nil -> %{top_ets: snapshot.top_ets}
        groups -> %{top_ets: snapshot.top_ets, process_groups: groups}
      end

    result =
      MemoryStat.store(%{
        pod_name: state.pod_name,
        container_type: state.container_type,
        beam_started_at: state.beam_started_at,
        rss_bytes: snapshot.rss_bytes,
        rss_hwm_bytes: snapshot.rss_hwm_bytes,
        vm_total_bytes: snapshot.vm_total_bytes,
        vm_processes_bytes: snapshot.vm_processes_bytes,
        vm_binary_bytes: snapshot.vm_binary_bytes,
        vm_ets_bytes: snapshot.vm_ets_bytes,
        vm_code_bytes: snapshot.vm_code_bytes,
        alloc_used_bytes: snapshot.alloc_used_bytes,
        alloc_allocated_bytes: snapshot.alloc_allocated_bytes,
        process_count: snapshot.process_count,
        atom_count: snapshot.atom_count,
        sample_duration_ms: snapshot.duration_ms,
        details: details
      })

    case result do
      {:ok, stat} ->
        Logger.info(
          "[MemoryCollector] sample pod=#{state.pod_name} rss=#{mb(snapshot.rss_bytes)} " <>
            "total=#{mb(snapshot.vm_total_bytes)} processes=#{mb(snapshot.vm_processes_bytes)} " <>
            "binary=#{mb(snapshot.vm_binary_bytes)} ets=#{mb(snapshot.vm_ets_bytes)} " <>
            "procs=#{snapshot.process_count} atoms=#{snapshot.atom_count} " <>
            "duration_ms=#{snapshot.duration_ms}"
        )

        {:ok, stat}

      {:error, changeset} ->
        Logger.warning(
          "[MemoryCollector] failed to store sample for pod=#{state.pod_name}: " <>
            inspect(changeset.errors)
        )

        {:error, changeset}
    end
  end

  @doc false
  def prune(state) do
    {deleted, _} = MemoryStat.prune(state.retention_days)

    if deleted > 0 do
      Logger.info(
        "[MemoryCollector] pruned #{deleted} node_memory_stats rows older than " <>
          "#{state.retention_days} days"
      )
    end

    :ok
  end

  # A bad value must not leave `retention_days` as something `MemoryStat.prune/1`
  # cannot match on — the FunctionClauseError would be swallowed by in_task/1
  # and pruning would stop for the lifetime of the pod.
  defp retention_days_from_config() do
    Config.module_get(__MODULE__, :retention_days, @default_retention_days)
    |> parse_retention_days()
  end

  defp parse_retention_days(days) when is_integer(days) and days > 0, do: days

  defp parse_retention_days(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {days, ""} when days > 0 -> days
      _ -> invalid_retention_days(value)
    end
  end

  defp parse_retention_days(value), do: invalid_retention_days(value)

  defp invalid_retention_days(value) do
    Logger.warning(
      "[MemoryCollector] invalid MEMORY_COLLECTOR_RETENTION_DAYS value #{inspect(value)}, " <>
        "expected a positive integer — falling back to #{@default_retention_days} days"
    )

    @default_retention_days
  end

  @doc false
  def pod_name() do
    System.get_env("HOSTNAME") || "sanbase-local-nohostname"
  end

  defp in_task(fun) do
    Task.Supervisor.start_child(Sanbase.TaskSupervisor, fn ->
      try do
        fun.()
      rescue
        e ->
          Logger.warning("[MemoryCollector] task failed: #{Exception.message(e)}")
      end
    end)
  end

  defp schedule(interval) do
    Process.send_after(self(), :sample, interval)
  end

  defp mb(nil), do: "-"
  defp mb(bytes), do: "#{Float.round(bytes / 1_048_576, 2)}MB"
end
