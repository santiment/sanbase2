defmodule Sanbase.Repo.Migrations.RemoveUnusedTables do
  use Ecto.Migration

  def up do
    drop(table(:project_btc_address))
    drop(table(:latest_btc_wallet_data))
  end

  def down do
    :ok
  end
end
