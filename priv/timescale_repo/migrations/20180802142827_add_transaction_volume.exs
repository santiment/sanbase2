defmodule Sanbase.TimescaleRepo.Migrations.AddTransactionVolume do
  use Ecto.Migration

  def up do
    create table(:eth_transaction_volume, primary_key: false) do
      add(:timestamp, :naive_datetime, primary_key: true)
      add(:contract_address, :string, primary_key: true)
      add(:transaction_volume, :float)
    end
  end

  def down do
    drop(table(:eth_transaction_volume))
  end
end
