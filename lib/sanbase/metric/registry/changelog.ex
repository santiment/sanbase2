defmodule Sanbase.Metric.Registry.Changelog do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Metric.Registry

  @change_triggers ["sync_apply", "change_request_approve", "change_request_undo"]

  schema "metric_registry_changelog" do
    field(:old, :string)
    field(:new, :string)

    field(:change_trigger, :string)

    belongs_to(:metric_registry, Registry, foreign_key: :metric_registry_id)

    timestamps()
  end

  def changeset(%__MODULE__{} = changelog, attrs) do
    changelog
    |> cast(attrs, [:old, :new, :metric_registry_id, :change_trigger])
    |> validate_required([:new, :metric_registry_id])
    |> validate_inclusion(:change_trigger, @change_triggers)
  end

  def create_changeset(%Ecto.Changeset{} = changeset, opts) do
    change_trigger = Keyword.fetch!(opts, :change_trigger)

    old = changeset.data
    new = changeset |> Ecto.Changeset.apply_changes()

    old = Jason.encode!(old)
    new = Jason.encode!(new)

    attrs = %{
      metric_registry_id: changeset.data.id,
      old: old,
      new: new,
      change_trigger: change_trigger
    }

    changeset(%__MODULE__{}, attrs)
  end

  def by_metric_registry_id(metric_registry_id) do
    query =
      from(changelog in __MODULE__, where: changelog.metric_registry_id == ^metric_registry_id)

    {:ok, Sanbase.Repo.all(query)}
  end

  def state_before_last_sync(metric_registry_id, nil = _last_sync_datetime) do
    query =
      from(changelog in __MODULE__,
        where: changelog.metric_registry_id == ^metric_registry_id,
        order_by: [asc: :id],
        limit: 1
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = struct ->
        Jason.decode(struct.old)

      nil ->
        {:error, "No changes known for #{metric_registry_id}"}
    end
  end

  def state_before_last_sync(metric_registry_id, %DateTime{} = last_sync_datetime) do
    query =
      from(changelog in __MODULE__,
        where:
          changelog.metric_registry_id == ^metric_registry_id and
            changelog.change_trigger == "sync_apply" and
            changelog.inserted_at <= ^last_sync_datetime,
        order_by: [asc: :id],
        limit: 1
      )

    case Sanbase.Repo.one(query) do
      %__MODULE__{} = struct ->
        Jason.decode(struct.old)

      nil ->
        {:error, "No changes known for #{metric_registry_id}"}
    end
  end
end
