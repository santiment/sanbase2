defmodule Sanbase.Ecosystem do
  @moduledoc ~s"""
  Module for managing the "ecosystems" postgres table

  There are many ecosystems and one project can belong to multiple ecosystems.
  The mapping is done in the Sanbase.ProjectEcosystemMapping module.

  This module provides functions for managing the ecosystems and fetching
  ecosystems, projects in an ecosystem, ecosystems of a projects, etc.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Project
  alias Sanbase.ProjectEcosystemMapping

  @type t :: %__MODULE__{
          ecosystem: String.t(),
          projects: list(%Project{}),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  @timestamps_opts [type: :utc_datetime]
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

  @spec get_id_by_name(String.t()) :: {:ok, non_neg_integer()} | {:error, String.t(0)}
  def get_id_by_name(ecosystem) do
    query = from(e in __MODULE__, where: e.ecosystem == ^ecosystem, select: e.id)

    case Sanbase.Repo.one(query) do
      nil -> {:error, "Ecosystem with name #{ecosystem} not found"}
      id -> {:ok, id}
    end
  end

  @spec all() :: list(t())
  def all do
    Sanbase.Repo.all(__MODULE__)
  end

  @spec get_ecosystems(:all | list(String.t())) :: {:ok, list(String.t())}
  def get_ecosystems(ecosystems_filter \\ :all) do
    query = from(e in __MODULE__, select: e.ecosystem)

    query =
      case ecosystems_filter do
        :all -> query
        ecosystems when is_list(ecosystems) -> where(query, [e], e.ecosystem in ^ecosystems)
      end

    {:ok, Sanbase.Repo.all(query)}
  end

  def get_ecosystem_by_name(ecosystem) do
    query = from(e in __MODULE__, where: e.ecosystem == ^ecosystem)

    case Sanbase.Repo.one(query) do
      nil -> {:error, "Ecosystem with name #{ecosystem} not found"}
      %__MODULE__{} = e -> {:ok, e}
    end
  end

  @spec get_ecosystems_with_projects(:all | list(String.t())) :: {:ok, list(map())}
  def get_ecosystems_with_projects(ecosystems_filter \\ :all) do
    with {:ok, ecosystems} <- get_ecosystems(ecosystems_filter),
         {:ok, ecosystem_to_projects_map} <- get_projects(ecosystems) do
      result =
        Enum.map(ecosystems, fn e ->
          %{name: e, projects: Map.get(ecosystem_to_projects_map, e)}
        end)

      {:ok, result}
    end
  end

  @spec create_ecosystem(String.t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_ecosystem(ecosystem) do
    %__MODULE__{}
    |> changeset(%{ecosystem: ecosystem})
    |> Sanbase.Repo.insert()
  end

  @spec add_ecosystem_to_project(non_neg_integer(), non_neg_integer() | String.t()) ::
          {:ok, t()} | {:error, String.t()} | {:error, Ecto.Changeset.t()}
  def add_ecosystem_to_project(project_id, ecosystem) when is_binary(ecosystem) do
    with {:ok, ecosystem} <- get_ecosystem_by_name(ecosystem) do
      add_ecosystem_to_project(project_id, ecosystem.id)
    end
  end

  def add_ecosystem_to_project(project_id, ecosystem_id) when is_integer(ecosystem_id) do
    ProjectEcosystemMapping.create(project_id, ecosystem_id)
  end

  @spec get_project_ecosystems(non_neg_integer()) :: {:ok, list(String.t())}
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
  @spec get_projects_by_ecosystem_names(list(String.t()), Keyword.t()) ::
          {:ok, list(%Project{})}
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

    projects = query |> Sanbase.Repo.all() |> apply_combinator(ecosystems, opts)
    {:ok, projects}
  end

  # Private functions

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

  defp get_projects(ecosystems) do
    projects = Sanbase.Project.List.projects()
    init = Map.new(ecosystems, fn e -> {e, []} end)

    ecosystem_to_projects_map =
      Enum.reduce(projects, init, fn %Project{} = p, acc ->
        Enum.reduce(p.ecosystems, acc, fn %__MODULE__{} = e, inner_acc ->
          Map.update(inner_acc, e.ecosystem, [p], &[p | &1])
        end)
      end)

    {:ok, ecosystem_to_projects_map}
  end
end
