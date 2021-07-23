defmodule Sanbase.Repo.Migrations.DropExchangeEthAddresses do
  use Ecto.Migration

  def up do
    drop(table(:exchange_eth_addresses))
  end

  def down, do: :ok
end
