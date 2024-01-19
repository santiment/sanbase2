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

  def get_ecosystems() do
    query = from(e in __MODULE__, select: e.ecosystem)
    {:ok, Sanbase.Repo.all(query)}
  end

  def create_ecosystem(ecosystem) do
    %__MODULE__{}
    |> changeset(%{ecosystem: ecosystem})
    |> Sanbase.Repo.insert()
  end

  def add_ecosystem_to_project(project_id, ecosystem_id) do
    ProjectEcosystemMapping.create(project_id, ecosystem_id)
  end

  def get_project_ecosystems(project_id) do
    query =
      from(e in __MODULE__,
        inner_join: m in ProjectEcosystemMapping,
        on: e.id == m.ecosystem_id,
        where: m.project_id == ^project_id,
        select: e.ecosystem
      )

    {:ok, Sanbase.Repo.all(query)}
  end

  @doc ~s"""
  Return all projects that belong to the given ecosystems.

  The opts can contain the option :combinator, which controls how the ecosystems
  are combined:
  - :all_of (default) - Return all projects that have all of the ecosystems.
  - :any_of - Return all projects that have at least one of the provided ecosystems

  """
  def get_projects_by_ecosystem_names(ecosystems, opts \\ []) do
    preloads = Project.preloads()

    query =
      from(p in Project,
        inner_join: m in ProjectEcosystemMapping,
        on: p.id == m.project_id,
        inner_join: e in __MODULE__,
        on: e.id == m.ecosystem_id,
        where: e.ecosystem in ^ecosystems,
        select: p,
        preload: ^preloads
      )

    projects = Sanbase.Repo.all(query) |> apply_combinator(ecosystems, opts)
    {:ok, projects}
  end

  defp apply_combinator(list, ecosystems, opts) do
    case Keyword.get(opts, :combinator, :all_of) do
      :any_of ->
        Enum.filter(list, fn p ->
          project_ecosystems = Enum.map(p.ecosystems, & &1.ecosystem)
          Enum.any?(ecosystems, &(&1 in project_ecosystems))
        end)

      :all_of ->
        Enum.filter(list, fn p ->
          project_ecosystems = Enum.map(p.ecosystems, & &1.ecosystem)
          Enum.all?(ecosystems, &(&1 in project_ecosystems))
        end)

      other ->
        raise(
          ArgumentError,
          """
          The get_projects_by_ecosystem_names/2 function can accept :any_of or :all_of as :combinator option.
          Got #{inspect(other)} instead
          """
        )
    end
  end
end
