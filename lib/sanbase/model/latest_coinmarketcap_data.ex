defmodule Sanbase.Model.LatestCoinmarketcapData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestCoinmarketcapData

  schema "latest_coinmarketcap_data" do
    field :coinmarketcap_id, :string
    field :name, :string
    field :market_cap_usd, :decimal
    field :price_usd, :decimal
    field :symbol, :string
    field :update_time, :utc_datetime
  end

  @doc false
  def changeset(%LatestCoinmarketcapData{} = latest_coinmarketcap_data, attrs \\ %{}) do
    latest_coinmarketcap_data
    |> cast(attrs, [:coinmarketcap_id, :name, :symbol, :price_usd, :market_cap_usd, :update_time])
    |> validate_required([:coinmarketcap_id, :update_time])
    |> unique_constraint(:coinmarketcap_id)
  end
end
