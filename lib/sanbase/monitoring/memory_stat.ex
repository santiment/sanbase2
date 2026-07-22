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
