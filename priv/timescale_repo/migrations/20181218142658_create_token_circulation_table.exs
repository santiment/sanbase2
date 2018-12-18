defmodule Sanbase.TimescaleRepo.Migrations.AddTokenCirculation do
  use Ecto.Migration

  def change do
    create_if_not_exists table(:eth_coin_circulation, primary_key: false) do
      add(:timestamp, :naive_datetime, primary_key: true)
      add(:contract_address, :string, primary_key: true)
      add(:"_-1d", :float)
    end
  end
end
