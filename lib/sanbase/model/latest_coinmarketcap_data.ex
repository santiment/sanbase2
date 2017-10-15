defmodule Sanbase.Model.LatestCoinmarketcapData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestCoinmarketcapData


  @primary_key{:id, :string, []}
  schema "latest_coinmarketcap_data" do
    field :market_cap_usd, :decimal
    field :name, :string
    field :price_usd, :decimal
    field :symbol, :string
    field :update_time, :naive_datetime
  end

  @doc false
  def changeset(%LatestCoinmarketcapData{} = latest_coinmarketcap_data, attrs) do
    latest_coinmarketcap_data
    |> cast(attrs, [:id, :name, :symbol, :price_usd, :market_cap_usd, :update_time])
    |> validate_required([:id, :name, :symbol, :price_usd, :market_cap_usd, :update_time])
  end
end
