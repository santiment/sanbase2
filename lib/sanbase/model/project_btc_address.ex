defmodule Sanbase.Model.ProjectBtcAddress do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{ProjectBtcAddress, Project}

  schema "project_btc_address" do
    field :address, :string
    belongs_to :project, Project
    field :project_transparency, :boolean, default: false
  end

  @doc false
  def changeset(%ProjectBtcAddress{} = project_btc_address, attrs \\ %{}) do
    project_btc_address
    |> cast(attrs, [:address, :project_id, :project_transparency])
    |> validate_required([:address, :project_id])
    |> unique_constraint(:address)
  end
end
