defmodule Sanbase.Repo.Migrations.CreateLatestEthWalletData do
  use Ecto.Migration

  def change do
    create table(:latest_eth_wallet_data, primary_key: false) do
      add :address, :text, primary_key: true
      add :balance, :real, null: false
      add :last_incoming, :timestamp
      add :last_outgoing, :timestamp
      add :tx_in, :real
      add :tx_out, :real
      add :update_time, :timestamp, null: false
    end

  end
end
