defmodule Sanbase.Monitoring.MemoryStat do
  @moduledoc """
  One row = one memory sample of one BEAM node (pod), taken every minute by
  `Sanbase.Monitoring.MemoryCollector`.

  `pod_name` comes from the `HOSTNAME` env var (the k8s pod name). Deployment
  pods get a new name on every rollout, so `pod_name` identifies one pod
  incarnation, not a stable series — `container_type` is the stable grouping
  dimension. StatefulSet pods (sanbase-web-N) keep their name across
  restarts, so the true identity of one BEAM lifetime is
  `(pod_name, beam_started_at)`.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @scalar_fields [
    :pod_name,
    :container_type,
    :beam_started_at,
    :rss_bytes,
    :rss_hwm_bytes,
    :vm_total_bytes,
    :vm_processes_bytes,
    :vm_binary_bytes,
    :vm_ets_bytes,
    :vm_code_bytes,
    :alloc_used_bytes,
    :alloc_allocated_bytes,
    :process_count,
    :atom_count,
    :sample_duration_ms
  ]

  @cast_fields [:details | @scalar_fields]

  schema "node_memory_stats" do
    field(:pod_name, :string)
    field(:container_type, :string)
    field(:beam_started_at, :utc_datetime)

    field(:rss_bytes, :integer)
    field(:rss_hwm_bytes, :integer)
    field(:vm_total_bytes, :integer)
    field(:vm_processes_bytes, :integer)
    field(:vm_binary_bytes, :integer)
    field(:vm_ets_bytes, :integer)
    field(:vm_code_bytes, :integer)
    field(:alloc_used_bytes, :integer)
    field(:alloc_allocated_bytes, :integer)

    field(:process_count, :integer)
    field(:atom_count, :integer)
    field(:sample_duration_ms, :integer)

    field(:details, :map, default: %{})

    timestamps()
  end

  @doc """
  Changeset for one sample. Only the identity and VM-wide fields are required:
  RSS needs /proc (absent on macOS dev) and the allocator totals depend on the
  allocator format, so both may legitimately be nil.
  """
  def changeset(%__MODULE__{} = stat, attrs) do
    stat
    |> cast(attrs, @cast_fields)
    |> validate_required([
      :pod_name,
      :container_type,
      :beam_started_at,
      :vm_total_bytes,
      :vm_processes_bytes,
      :vm_binary_bytes,
      :vm_ets_bytes,
      :vm_code_bytes,
      :process_count,
      :atom_count,
      :sample_duration_ms
    ])
  end

  @doc """
  Insert one sample. Returns `{:ok, stat}` or `{:error, changeset}`.
  """
  def store(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  # Deleting in batches keeps one statement from locking a large row range:
  # at steady state a run removes ~1h of rows, but lowering the retention
  # window makes the next run delete everything between the old and new one.
  @prune_batch_size 10_000

  @doc """
  Delete samples older than `days`, in batches. Returns `{deleted_count, nil}`.
  Safe to run concurrently from many pods.
  """
  def prune(days) when is_integer(days) and days > 0 do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86_400, :second)

    {prune_batches(cutoff, 0), nil}
  end

  defp prune_batches(cutoff, deleted_so_far) do
    ids =
      from(s in __MODULE__,
        where: s.inserted_at < ^cutoff,
        select: s.id,
        limit: @prune_batch_size
      )

    {deleted, _} = from(s in __MODULE__, where: s.id in subquery(ids)) |> Repo.delete_all()

    case deleted do
      @prune_batch_size -> prune_batches(cutoff, deleted_so_far + deleted)
      _ -> deleted_so_far + deleted
    end
  end

  @doc """
  Latest sample per pod among pods that reported within the last
  `recent_minutes` — the "live pods" overview.
  """
  def latest_per_pod(recent_minutes \\ 5) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-recent_minutes * 60, :second)

    from(s in __MODULE__,
      where: s.inserted_at > ^cutoff,
      distinct: s.pod_name,
      order_by: [asc: s.pod_name, desc: s.inserted_at, desc: s.id]
    )
    |> Repo.all()
    |> Enum.sort_by(&{&1.container_type, &1.pod_name})
  end

  @doc """
  Scalar time series for one pod over the last `hours`, oldest first.
  `details` is excluded to keep the payload small.
  """
  def pod_series(pod_name, hours \\ 24) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)

    from(s in __MODULE__,
      where: s.pod_name == ^pod_name and s.inserted_at > ^cutoff,
      order_by: [asc: s.inserted_at],
      select: map(s, ^([:id, :inserted_at | @scalar_fields] -- [:pod_name, :container_type]))
    )
    |> Repo.all()
  end

  @chart_metrics [
    :rss_bytes,
    :rss_hwm_bytes,
    :vm_total_bytes,
    :vm_processes_bytes,
    :vm_binary_bytes,
    :vm_ets_bytes,
    :process_count
  ]

  @doc """
  Fields `multi_pod_metric_series/4` accepts. Interpolated into a query
  fragment, so the allowed list is fixed here rather than taken from callers.
  """
  def chart_metrics(), do: @chart_metrics

  @doc """
  One metric across many pods over the last `hours`, for charting:
  `[%{name: pod_name, points: [[unix_seconds, value], ...]}]`, points oldest
  first. A point with a nil value is a real gap in reporting and is kept as
  one, so the chart breaks the line instead of drawing through the outage.

  Aggregated into time buckets by Postgres rather than fetched raw: over a
  7d window that is ~1500 rows per pod instead of ~10k. Each bucket keeps its
  peak, because the minute-long spikes are the point of the chart.
  """
  def multi_pod_metric_series(pod_names, metric, hours, max_points \\ 1500)
      when metric in @chart_metrics do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)
    seconds = bucket_seconds(hours, max_points)

    from(s in __MODULE__,
      where: s.pod_name in ^pod_names and s.inserted_at > ^cutoff,
      group_by: [s.pod_name, selected_as(:bucket)],
      order_by: [asc: s.pod_name, asc: selected_as(:bucket)],
      select: {
        s.pod_name,
        selected_as(
          fragment(
            "(floor(extract(epoch from ?) / ?) * ?)::bigint",
            s.inserted_at,
            ^seconds,
            ^seconds
          ),
          :bucket
        ),
        max(field(s, ^metric))
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn {pod, _bucket, _v} -> pod end)
    |> Enum.sort_by(fn {pod, _rows} -> pod end)
    |> Enum.map(fn {pod, rows} ->
      %{name: pod, points: for({_pod, bucket, v} <- rows, do: [bucket, v])}
    end)
  end

  # Floor at half the one-minute sampling interval so that on short windows
  # consecutive samples always land in buckets of their own — bucketing must
  # not cost resolution the raw data actually has.
  @min_bucket_seconds 30

  defp bucket_seconds(hours, max_points) do
    Enum.max([div(hours * 3600, max_points), @min_bucket_seconds])
  end

  @doc """
  Chart series built from rows already fetched with `pod_series/2`, one entry
  per `{label, getter}` pair: `[%{name: label, points: [[unix_seconds, value],
  ...]}]`. `getter` is either a field of the row or a function of the whole
  row, for values derived from several fields (see `utilization/1`).

  Samples that did not record a value stay in the series as nil points:
  dropping them would make the chart draw a straight line across the gap,
  which reads as "steady" when it actually means "no data".
  """
  def labeled_series(rows, labeled_getters, max_points \\ 1500) do
    for {label, getter} <- labeled_getters do
      points =
        for row <- rows do
          [to_unix(row.inserted_at), get_value(row, getter)]
        end

      %{name: label, points: downsample(points, max_points)}
    end
  end

  defp get_value(row, getter) when is_function(getter, 1), do: getter.(row)
  defp get_value(row, key) when is_atom(key), do: Map.get(row, key)

  @doc """
  Allocator utilization of one sample (used blocks / allocated carriers) as a
  percent, `nil` when the allocator stats are missing. Falling utilization
  while RSS rises = fragmentation or carrier ratchet — RSS growth without
  matching live-data growth.
  """
  def utilization(%{alloc_used_bytes: used, alloc_allocated_bytes: allocated})
      when is_integer(used) and is_integer(allocated) and allocated > 0 do
    Float.round(used / allocated * 100, 1)
  end

  def utilization(_row), do: nil

  defp to_unix(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  end

  # Keep the peak of each bucket instead of every Nth point: a stride drops
  # whole samples, and the one-minute spike it happens to skip is exactly what
  # someone opens this dashboard to find.
  defp downsample(points, max_points) when length(points) > max_points do
    step = ceil(length(points) / max_points)

    points
    |> Enum.chunk_every(step)
    |> Enum.map(&bucket_peak/1)
  end

  defp downsample(points, _max_points), do: points

  defp bucket_peak([[time, _value] | _] = bucket) do
    case Enum.reject(bucket, fn [_t, value] -> is_nil(value) end) do
      [] -> [time, nil]
      values -> Enum.max_by(values, fn [_t, value] -> value end)
    end
  end

  @known_pods_days 7

  @doc """
  Every pod that reported within the last `days`, with its oldest and newest
  snapshot times and sample count, newest-reporting first. Powers the
  "known pods" history list shown when pods are not live.

  Bounded on purpose: this aggregates without an index-only path (the group
  includes `container_type`), so scanning the full retention window would mean
  a full-table aggregate on every dashboard refresh.
  """
  def known_pods(limit \\ 100, days \\ @known_pods_days) do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86_400, :second)

    from(s in __MODULE__,
      where: s.inserted_at > ^cutoff,
      group_by: [s.pod_name, s.container_type],
      select: %{
        pod_name: s.pod_name,
        container_type: s.container_type,
        first_seen: min(s.inserted_at),
        last_seen: max(s.inserted_at),
        samples: count(s.id)
      },
      order_by: [desc: max(s.inserted_at)],
      limit: ^limit
    )
    |> Repo.all()
  end

  @doc """
  Most recent sample of one pod regardless of how long ago it reported —
  used to show history of pods that stopped reporting (replaced by a newer
  deployment) and whose rows are not yet pruned.
  """
  def latest_for_pod(pod_name) do
    from(s in __MODULE__,
      where: s.pod_name == ^pod_name,
      order_by: [desc: s.inserted_at, desc: s.id],
      limit: 1
    )
    |> Repo.one()
  end

  @doc """
  Most recent sample of one pod that has process-group details
  (they are only collected on every Nth sample).
  """
  def latest_details(pod_name) do
    from(s in __MODULE__,
      where: s.pod_name == ^pod_name,
      order_by: [desc: s.inserted_at, desc: s.id],
      limit: 10
    )
    |> Repo.all()
    |> Enum.find(&match?(%{"process_groups" => [_ | _]}, &1.details))
    |> case do
      nil -> latest_for_pod(pod_name)
      stat -> stat
    end
  end
end
