defmodule Sanbase.Repo.Migrations.CreateLatestCoinmarketcapData do
  use Ecto.Migration

  def change do
    create table(:latest_coinmarketcap_data) do
      add :coinmaketcap_id, :text
      add :name, :string
      add :symbol, :string
      add :price_usd, :numeric
      add :market_cap_usd, :numeric
      add :update_time, :timestamp, null: false
    end

  end
end
