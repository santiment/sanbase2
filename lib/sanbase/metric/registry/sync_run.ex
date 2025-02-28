defmodule Sanbase.Metric.Registry.SyncRun do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  @pubsub_topic "sanbase_metric_registry_sync"

  schema "metric_registry_sync_runs" do
    field(:uuid, :string)
    field(:sync_type, :string)
    field(:status, :string)
    field(:content, :string)
    field(:actual_changes, :string)
    field(:errors, :string)

    field(:is_dry_run, :boolean)

    timestamps()
  end

  def changeset(%__MODULE__{} = sync, attrs) do
    sync
    |> cast(attrs, [:uuid, :content, :actual_changes, :status, :errors, :sync_type, :is_dry_run])
    |> validate_inclusion(:status, ["scheduled", "executing", "completed", "failed", "cancelled"])
    |> validate_inclusion(:sync_type, ["outgoing", "incoming"])
  end

  def last_syncs(limit) do
    from(sync in __MODULE__, order_by: [desc: sync.id], limit: ^limit)
    |> Sanbase.Repo.all()
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Sanbase.Repo.insert()
  end

  def update(%__MODULE__{} = sync, attrs) do
    sync
    |> changeset(attrs)
    |> Sanbase.Repo.update()
  end

  def update_status(%__MODULE__{} = sync, status, errors \\ nil) do
    sync
    |> changeset(%{status: status, errors: errors})
    |> Sanbase.Repo.update()
    |> case do
      {:ok, struct} ->
        SanbaseWeb.Endpoint.broadcast_from(self(), @pubsub_topic, "update_status", %{})
        {:ok, struct}

      {:error, error} ->
        {:error, error}
    end
  end

  def by_uuid(uuid, sync_type \\ "outgoing") do
    query = from(sync in __MODULE__, where: sync.uuid == ^uuid and sync.sync_type == ^sync_type)

    case Sanbase.Repo.one(query) do
      nil -> {:error, "Sync with uuid #{uuid} not found"}
      sync -> {:ok, sync}
    end
  end

  def all_with_status(status) do
    from(sync in __MODULE__, where: sync.status == ^status)
    |> Sanbase.Repo.all()
  end
end
