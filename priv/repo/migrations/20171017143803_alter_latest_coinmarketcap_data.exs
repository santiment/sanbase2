defmodule Sanbase.Repo.Migrations.AlterLatestCoinmarketcapData do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add :rank, :integer
      add :price_btc, :decimal
      add :volume_usd_24h, :decimal
      add :available_supply, :decimal
      add :total_supply, :decimal
      add :percent_change_1h, :decimal
      add :percent_change_24h, :decimal
      add :percent_change_7d, :decimal
    end
  end
end
