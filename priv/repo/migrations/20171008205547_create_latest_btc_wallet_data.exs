defmodule Sanbase.Repo.Migrations.CreateLatestBtcWalletData do
  use Ecto.Migration

  def change do
    create table(:latest_btc_wallet_data) do
      add :address, :string, null: false
      add :satoshi_balance, :decimal, null: false
      add :update_time, :timestamp, null: false
    end

    create unique_index(:latest_btc_wallet_data, [:address])
  end
end
