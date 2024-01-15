defmodule Sanbase.Ecosystem do
  @moduledoc ~s"""
  Module for managing the "github_organziations" postgres table

  In order to have multiple github organizations per project we store
  the github data in a separate table
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.ProjectEcosystemMapping
  alias Sanbase.Project

  schema "ecosystems" do
    field(:ecosystem, :string)

    many_to_many(
      :projects,
      Project,
      join_through: "project_ecosystem_mappings",
      on_replace: :delete,
      on_delete: :delete_all
    )

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = market_segment, attrs \\ %{}) do
    market_segment
    |> cast(attrs, [:ecosystem])
    |> validate_required([:ecosystem])
    |> unique_constraint(:ecosystem)
  end

  def all(), do: Sanbase.Repo.all(__MODULE__)

  def add_ecosystem(ecosystem) do
    %__MODULE__{}
    |> changeset(%{ecosystem: ecosystem})
    |> Sanbase.Repo.insert()
  end

  def add_ecosystem_to_project(project_id, ecosystem_id) do
    ProjectEcosystemMapping.create(project_id, ecosystem_id)
  end

  def get_project_ecosystems(project_id) do
    from(e in __MODULE__,
      inner_join: m in ProjectEcosystemMapping,
      on: e.id == m.ecosystem_id,
      where: m.project_id == ^project_id,
      select: e.ecosystem
    )
  end
end
