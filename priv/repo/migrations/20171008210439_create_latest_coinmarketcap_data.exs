defmodule Sanbase.Repo.Migrations.CreateLatestCoinmarketcapData do
  use Ecto.Migration

  def change do
    create table(:latest_coinmarketcap_data) do
      add :coinmarketcap_id, :string, null: false
      add :name, :string
      add :symbol, :string
      add :price_usd, :decimal
      add :market_cap_usd, :decimal
      add :update_time, :timestamp, null: false
    end

    create unique_index(:latest_coinmarketcap_data, [:coinmarketcap_id])
  end
end
