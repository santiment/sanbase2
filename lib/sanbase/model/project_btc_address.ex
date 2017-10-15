defmodule Sanbase.Model.ProjectBtcAddress do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{ProjectBtcAddress, Project}


  @primary_key{:address, :string, []}
  schema "project_btc_address" do
    # field :address, :string
    belongs_to :project, Project
  end

  @doc false
  def changeset(%ProjectBtcAddress{} = project_btc_address, attrs) do
    project_btc_address
    |> cast(attrs, [:address])
    |> validate_required([:address])
  end
end
