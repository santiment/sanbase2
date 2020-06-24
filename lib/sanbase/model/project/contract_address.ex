defmodule Sanbase.Model.Project.ContractAddress do
  use Ecto.Schema

  import Ecto.Changeset

  alias Sanbase.Model.Project

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
  end

  def list_to_main_contract_address(list) when is_list(list) do
    Enum.find(list, &(&1.label == "main")) || List.first(list)
  end
end
