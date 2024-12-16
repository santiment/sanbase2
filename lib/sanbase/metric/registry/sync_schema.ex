defmodule Sanbase.Metric.Registry.SyncSchema do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  schema "metric_registry_syncs" do
    field(:uuid, :string)
    field(:status, :string)
    field(:content, :string)
    field(:errors, :string)

    timestamps()
  end

  def changeset(%__MODULE__{} = sync, attrs) do
    sync
    |> cast(attrs, [:uuid, :content, :status, :errors])
    |> validate_inclusion(:status, ["scheduled", "executing", "completed", "failed"])
  end

  def create(content) do
    %__MODULE__{}
    |> changeset(%{content: content, status: "scheduled", uuid: Ecto.UUID.generate()})
    |> Sanbase.Repo.insert()
  end

  def update_status(%__MODULE__{} = struct, status, errors \\ nil) do
    struct
    |> changeset(%{status: status, errors: errors})
    |> Sanbase.Repo.update()
  end

  def by_uuid(uuid) do
    query = from(sync in __MODULE__, where: sync.uuid == ^uuid)

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
