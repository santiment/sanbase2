defmodule Sanbase.Repo.Migrations.AddIntegerIdToLatestCmcData do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add(:coinmarketcap_integer_id, :integer)
    end
  end
end
