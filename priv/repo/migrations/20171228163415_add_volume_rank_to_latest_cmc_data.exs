defmodule Sanbase.Repo.Migrations.AddVolumeRankToLatestCmcData do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add :rank, :integer
      add :volume_usd, :decimal
      add :available_supply, :decimal
      add :total_supply, :decimal
    end
  end
end
