defmodule Sanbase.TimescaleRepo.Migrations.AddBurnRate do
  use Ecto.Migration

  def up do
    create table(:eth_burn_rate, primary_key: false) do
      add(:timestamp, :naive_datetime, primary_key: true)
      add(:contract_address, :string, primary_key: true)
      add(:burn_rate, :float)
    end
  end

  def down do
    drop(table(:eth_burn_rate))
  end
end
