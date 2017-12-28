defmodule Sanbase.Model.LatestCoinmarketcapData do
  use Ecto.Schema
  import Ecto.Changeset
  alias Sanbase.Model.LatestCoinmarketcapData

  schema "latest_coinmarketcap_data" do
    field :coinmarketcap_id, :string
    field :name, :string
    field :symbol, :string
    field :rank, :integer
    field :price_usd, :decimal
    field :volume_24h_usd, :decimal
    field :market_cap_usd, :decimal
    field :update_time, Ecto.DateTime
  end

  @doc false
  def changeset(%LatestCoinmarketcapData{} = latest_coinmarketcap_data, attrs \\ %{}) do
    latest_coinmarketcap_data
    |> cast(attrs, [:coinmarketcap_id, :name, :symbol, :price_usd, :market_cap_usd, :rank, :volume_24h_usd, :update_time])
    |> validate_required([:coinmarketcap_id, :update_time])
    |> unique_constraint(:coinmarketcap_id)
  end
end
