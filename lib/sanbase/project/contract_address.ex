defmodule Sanbase.Project.ContractAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Project

  schema "contract_addresses" do
    field(:address, :string)
    field(:decimals, :integer)
    field(:label, :string)
    field(:description, :string)

    belongs_to(:project, Project)

    timestamps()
  end

  def changeset(%__MODULE__{} = contract, attrs \\ %{}) do
    contract
    |> cast(attrs, [:address, :decimals, :label, :description, :project_id])
    |> validate_required([:address, :project_id])
  end

  @doc ~s"""
  Add contract to a project.
  """
  @spec add_contract(%Project{}, %{
          required(:address) => address,
          optional(:decimals) => decimals,
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
      label: Map.get(attrs, :label, "main"),
      project_id: project_id
    }

    %__MODULE__{}
    |> changeset(map)
    |> Sanbase.Repo.insert(
      on_conflict: [set: [label: map.label, decimals: map.decimals]],
      conflict_target: [:address, :project_id]
    )
  end

  def list_to_main_contract_address(list) when is_list(list) do
    Enum.find(list, &(&1.label == "main")) || List.first(list)
  end

  def list_to_latest_onchain_contract_address(list) when is_list(list) do
    Enum.find(list, &(&1.label == "latest_onchain_contract")) ||
      Enum.find(list, &(&1.label == "main")) ||
      List.first(list)
  end
end
