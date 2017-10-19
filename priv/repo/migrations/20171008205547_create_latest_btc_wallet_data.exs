defmodule Sanbase.Repo.Migrations.CreateLatestBtcWalletData do
  use Ecto.Migration

  def change do
    create table(:latest_btc_wallet_data) do
      add :address, :text, unique: true
      add :satoshi_balance, :real, null: false
      add :update_time, :timestamp, null: false
    end

  end
end
