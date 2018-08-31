defmodule Sanbase.Repo.Migrations.RemoveEthLatestWalletDataTable do
  use Ecto.Migration

  def change do
    drop(table(:latest_eth_wallet_data))
  end
end
