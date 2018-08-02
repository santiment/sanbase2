defmodule Sanbase.TimescaleRepo.Migrations.AddDailyActiveAddresses do
  use Ecto.Migration

  def up do
    create table(:eth_daily_active_addresses, primary_key: false) do
      add(:timestamp, :naive_datetime, primary_key: true)
      add(:contract_address, :string, primary_key: true)
      add(:active_addresses, :integer)
    end
  end

  def down do
    drop(table(:eth_daily_active_addresses))
  end
end
