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

  def changeset(%__MODULE__{} = stat, attrs) do
    stat
    |> cast(attrs, @scalar_fields ++ [:details])
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

  def store(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Delete samples older than `days`. Safe to run concurrently from many pods.
  """
  def prune(days) when is_integer(days) and days > 0 do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-days * 86_400, :second)

    from(s in __MODULE__, where: s.inserted_at < ^cutoff)
    |> Repo.delete_all()
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

  def chart_metrics(), do: @chart_metrics

  @doc """
  One metric across many pods over the last `hours`, for charting:
  `[%{name: pod_name, points: [[unix_seconds, value], ...]}]`, points oldest
  first, nil values dropped. Series longer than `max_points` are downsampled
  by taking every Nth point.
  """
  def multi_pod_metric_series(pod_names, metric, hours, max_points \\ 1500)
      when metric in @chart_metrics do
    cutoff = NaiveDateTime.utc_now() |> NaiveDateTime.add(-hours * 3600, :second)

    from(s in __MODULE__,
      where: s.pod_name in ^pod_names and s.inserted_at > ^cutoff,
      order_by: [asc: s.inserted_at],
      select: {s.pod_name, s.inserted_at, field(s, ^metric)}
    )
    |> Repo.all()
    |> Enum.group_by(fn {pod, _t, _v} -> pod end)
    |> Enum.sort_by(fn {pod, _rows} -> pod end)
    |> Enum.map(fn {pod, rows} ->
      points =
        for {_pod, t, v} <- rows, is_integer(v), do: [to_unix(t), v]

      %{name: pod, points: downsample(points, max_points)}
    end)
  end

  @doc """
  The VM memory buckets of one pod over the last `hours`:
  `[%{name: label, points: [[unix_seconds, value], ...]}]`. Answers "which
  bucket of live data grows".
  """
  def pod_buckets_series(pod_name, hours, max_points \\ 1500) do
    pod_series(pod_name, hours)
    |> series_for_keys(
      [
        {"OS RSS", :rss_bytes},
        {"VM total", :vm_total_bytes},
        {"VM processes", :vm_processes_bytes},
        {"VM binary", :vm_binary_bytes},
        {"VM ETS", :vm_ets_bytes}
      ],
      max_points
    )
  end

  @doc """
  The three memory-accounting layers of one pod (plus the RSS high-water
  mark) over the last `hours`. The gaps name the cause of RSS growth:
  allocated − used = carrier slack (spike ratchet / fragmentation, not a
  leak); RSS − allocated = native/NIF memory invisible to the VM; RSS
  converging toward a flat early high-water = past spike, not a leak.
  """
  def pod_layers_series(pod_name, hours, max_points \\ 1500) do
    pod_series(pod_name, hours)
    |> series_for_keys(
      [
        {"RSS high-water", :rss_hwm_bytes},
        {"OS RSS", :rss_bytes},
        {"Alloc allocated (carriers)", :alloc_allocated_bytes},
        {"Alloc used (blocks)", :alloc_used_bytes},
        {"VM total", :vm_total_bytes}
      ],
      max_points
    )
  end

  @doc """
  Allocator utilization (used blocks / allocated carriers) of one pod as a
  percent series. Falling utilization while RSS rises = fragmentation or
  carrier ratchet — RSS growth without matching live-data growth.
  """
  def pod_alloc_util_series(pod_name, hours, max_points \\ 1500) do
    points =
      for row <- pod_series(pod_name, hours),
          is_integer(row.alloc_used_bytes),
          is_integer(row.alloc_allocated_bytes),
          row.alloc_allocated_bytes > 0 do
        [
          to_unix(row.inserted_at),
          Float.round(row.alloc_used_bytes / row.alloc_allocated_bytes * 100, 1)
        ]
      end

    [%{name: "Allocator utilization", points: downsample(points, max_points)}]
  end

  defp series_for_keys(rows, label_keys, max_points) do
    for {label, key} <- label_keys do
      points =
        for row <- rows, v = Map.get(row, key), is_integer(v) do
          [to_unix(row.inserted_at), v]
        end

      %{name: label, points: downsample(points, max_points)}
    end
  end

  defp to_unix(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> DateTime.to_unix()
  end

  defp downsample(points, max_points) when length(points) > max_points do
    step = ceil(length(points) / max_points)
    Enum.take_every(points, step)
  end

  defp downsample(points, _max_points), do: points

  @doc """
  Every pod present in the retention window, with its oldest and newest
  snapshot times and sample count, newest-reporting first. Powers the
  "known pods" history list shown when pods are not live.
  """
  def known_pods(limit \\ 100) do
    from(s in __MODULE__,
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
      order_by: [desc: s.inserted_at],
      limit: 10
    )
    |> Repo.all()
    |> Enum.find(fn s -> match?(%{"process_groups" => [_ | _]}, s.details) end)
    |> case do
      nil ->
        from(s in __MODULE__,
          where: s.pod_name == ^pod_name,
          order_by: [desc: s.inserted_at],
          limit: 1
        )
        |> Repo.one()

      stat ->
        stat
    end
  end
end
