defmodule Sanbase.Repo.Migrations.CreateExchangeEthAddresses do
  use Ecto.Migration

  def change do
    create table(:exchange_eth_addresses) do
      add :address, :string, null: :false
      add :name, :string, null: :false
      add :comments, :text
    end

    create unique_index(:exchange_eth_addresses, [:address])
  end
end
