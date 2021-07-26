defmodule Sanbase.Repo.Migrations.AddPriceBtcLatestcoinmarketcap do
  use Ecto.Migration

  def change do
    alter table(:latest_coinmarketcap_data) do
      add(:price_btc, :decimal)
    end
  end
end
