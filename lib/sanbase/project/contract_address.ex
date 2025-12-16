defmodule Sanbase.Project.ContractAddress do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Project

  schema "contract_addresses" do
    field(:address, :string)
    field(:decimals, :integer)
    field(:label, :string)
    field(:description, :string)

    field(:decimals_scrape_attempted_at, :utc_datetime)

    belongs_to(:project, Project)

    timestamps()
  end

  def changeset(%__MODULE__{} = contract, attrs \\ %{}) do
    contract
    |> cast(attrs, [
      :address,
      :decimals,
      :label,
      :description,
      :project_id,
      :decimals_scrape_attempted_at
    ])
    |> validate_required([:address, :project_id])
    |> unique_constraint([:project_id, :address],
      message: "The combination of project and contract address must be unique."
    )
  end

  @doc ~s"""
  Add contract to a project.
  """
  @spec add_contract(%Project{}, %{
          required(:address) => address,
          optional(:decimals) => decimals,
          optional(:description) => String.t(),
          optional(:label) => String.t()
        }) :: {:ok, %__MODULE__{}} | {:error, any()}
        when address: String.t(), decimals: non_neg_integer()
  def add_contract(
        %Project{id: project_id},
        %{} = attrs
      ) do
    map = %{
      address: Map.get(attrs, :address),
      decimals: Map.get(attrs, :decimals),
      label: Map.get(attrs, :label),
      description: Map.get(attrs, :description),
      project_id: project_id
    }

    %__MODULE__{}
    |> changeset(map)
    |> Sanbase.Repo.insert(
      on_conflict: [set: [label: map.label, decimals: map.decimals, description: map.description]],
      conflict_target: [:address, :project_id]
    )
  end

  def list_to_main_contract_address(list) when is_list(list) do
    list
    |> Enum.reject(&is_nil(&1.decimals))
    |> Enum.find(&(&1.label == "main")) || List.first(list)
  end

  def list_to_latest_onchain_contract_address(list) when is_list(list) do
    list = list |> Enum.reject(&is_nil(&1.decimals))

    Enum.find(list, &(&1.label == "latest_onchain_contract")) ||
      Enum.find(list, &(&1.label == "main")) ||
      List.first(list)
  end

  def delete_by_project_id_and_address(project_id, address) do
    from(ca in __MODULE__,
      where: ca.project_id == ^project_id and ca.address == ^address
    )
    |> Sanbase.Repo.delete_all()
  end

  def all_with_infrastructure() do
    from(ca in __MODULE__,
      where: not is_nil(ca.decimals),
      join: p in assoc(ca, :project),
      join: i in assoc(p, :infrastructure),
      preload: [:project, project: [:infrastructure]]
    )
    |> Sanbase.Repo.all()
  end
end
