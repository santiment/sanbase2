defmodule Sanbase.Metric.Registry.Changelog do
  @moduledoc false
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Metric.Registry

  schema "metric_registry_changelog" do
    field(:old, :string)
    field(:new, :string)

    belongs_to(:metric_registry, Registry, foreign_key: :metric_registry_id)

    timestamps()
  end

  def changeset(%__MODULE__{} = changelog, attrs) do
    changelog
    |> cast(attrs, [:old, :new, :metric_registry_id])
    |> validate_required([:new, :metric_registry_id])
  end

  def create_changest(%Ecto.Changeset{} = changeset) do
    old = changeset.data
    new = Ecto.Changeset.apply_changes(changeset)

    old = Jason.encode!(old)
    new = Jason.encode!(new)

    attrs = %{metric_registry_id: changeset.data.id, old: old, new: new}

    changeset(%__MODULE__{}, attrs)
  end

  def by_metric_registry_id(metric_registry_id) do
    query =
      from(changelog in __MODULE__, where: changelog.metric_registry_id == ^metric_registry_id)

    {:ok, Sanbase.Repo.all(query)}
  end
end
