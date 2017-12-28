defmodule Sanbase.Repo.Migrations.AddVolumeRankToLatestCmcData do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add :rank, :integer
      add :volume_24h_usd, :decimal
    end
  end
end
