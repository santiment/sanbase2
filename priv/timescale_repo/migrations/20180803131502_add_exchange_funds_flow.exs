defmodule Sanbase.TimescaleRepo.Migrations.AddExchangeFundsFlow do
  use Ecto.Migration
  def up do
    create table(:eth_exchange_funds_flow, primary_key: false) do
      add(:timestamp, :naive_datetime, primary_key: true)
      add(:contract_address, :string, primary_key: true)
      add(:incoming_exchange_funds, :float)
      add(:outgoing_exchange_funds, :float)
    end
  end

  def down do
    drop(table(:eth_exchange_funds_flow))
  end
end
