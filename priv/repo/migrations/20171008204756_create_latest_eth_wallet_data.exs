defmodule Sanbase.Repo.Migrations.CreateLatestEthWalletData do
  use Ecto.Migration

  def change do
    create table(:latest_eth_wallet_data) do
      add(:address, :string, null: false)
      add(:balance, :decimal, null: false)
      add(:last_incoming, :timestamp)
      add(:last_outgoing, :timestamp)
      add(:tx_in, :decimal)
      add(:tx_out, :decimal)
      add(:update_time, :timestamp, null: false)
    end

    create(unique_index(:latest_eth_wallet_data, [:address]))
  end
end
