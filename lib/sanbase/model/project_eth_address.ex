defmodule Sanbase.Model.ProjectEthAddress do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{ProjectEthAddress, Project}


  @primary_key{:address, :string, []}
  schema "project_eth_address" do
    # field :address, :string
    belongs_to :project, Project
  end

  @doc false
  def changeset(%ProjectEthAddress{} = project_eth_address, attrs) do
    project_eth_address
    |> cast(attrs, [:address])
    |> validate_required([:address])
  end
end
