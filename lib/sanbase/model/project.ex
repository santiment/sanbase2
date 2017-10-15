defmodule Sanbase.Model.Project do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.{Project, ProjectEthAddress, ProjectBtcAddress}


  schema "project" do
    field :name, :string
    field :ticker, :string
    field :logo_url, :string
    field :coinmarketcap_id, :string
    has_many :eth_addresses, ProjectEthAddress
    has_many :btc_addresses, ProjectBtcAddress
  end

  @doc false
  def changeset(%Project{} = project, attrs) do
    project
    |> cast(attrs, [:name, :ticker, :logo_url, :coinmarketcap_id])
    |> validate_required([:name, :ticker, :logo_url, :coinmarketcap_id])
    |> unique_constraint(:name)
    |> unique_constraint(:coinmarketcap_id)
  end
end
