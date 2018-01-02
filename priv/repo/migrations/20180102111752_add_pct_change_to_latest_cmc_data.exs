defmodule Sanbase.Repo.Migrations.AddPctChangeToLatestCmcData do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add :percent_change_1h, :decimal
      add :percent_change_24h, :decimal
      add :percent_change_7d, :decimal
    end
  end
end
