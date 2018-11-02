defmodule Sanbase.Repo.Migrations.RenameExchangeEthAddresses do
  use Ecto.Migration

  def up do
    rename(table(:exchange_eth_addresses), to: table(:exchange_addresses))
  end

  def down, do: :ok
end
