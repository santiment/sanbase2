defmodule Sanbase.Repo.Migrations.CreateLatestCoinmarketcapData do
  use Ecto.Migration

  def change do
    create table(:latest_coinmarketcap_data, primary_key: false) do
      add :id, :text, primary_key: true
      add :name, :text
      add :symbol, :text
      add :price_usd, :numeric
      add :market_cap_usd, :numeric
      add :update_time, :timestamp, null: false
    end

  end
end
