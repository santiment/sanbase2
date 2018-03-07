defmodule Sanbase.Model.LatestCoinmarketcapData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestCoinmarketcapData

  schema "latest_coinmarketcap_data" do
    field(:coinmarketcap_id, :string)
    field(:name, :string)
    field(:symbol, :string)
    field(:rank, :integer)
    field(:price_usd, :decimal)
    field(:price_btc, :decimal)
    field(:volume_usd, :decimal)
    field(:market_cap_usd, :decimal)
    field(:available_supply, :decimal)
    field(:total_supply, :decimal)
    field(:percent_change_1h, :decimal)
    field(:percent_change_24h, :decimal)
    field(:percent_change_7d, :decimal)
    field(:update_time, :naive_datetime)
  end

  @doc false
  def changeset(%LatestCoinmarketcapData{} = latest_coinmarketcap_data, attrs \\ %{}) do
    latest_coinmarketcap_data
    |> cast(attrs, [
      :coinmarketcap_id,
      :name,
      :symbol,
      :price_usd,
      :price_btc,
      :market_cap_usd,
      :rank,
      :volume_usd,
      :available_supply,
      :total_supply,
      :percent_change_1h,
      :percent_change_24h,
      :percent_change_7d,
      :update_time
    ])
    |> validate_required([:coinmarketcap_id, :update_time])
    |> unique_constraint(:coinmarketcap_id)
  end
end
