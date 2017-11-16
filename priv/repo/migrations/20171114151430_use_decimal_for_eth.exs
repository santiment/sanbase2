defmodule Sanbase.Repo.Migrations.UseDecimalForEth do
  use Ecto.Migration

  def up do
    alter table(:latest_eth_wallet_data) do
      modify :tx_in, :decimal
      modify :tx_out, :decimal
      modify :balance, :decimal
      modify :last_incoming, :utc_datetime
      modify :last_outgoing, :utc_datetime
      modify :update_time, :utc_datetime
    end
  end

  def down do
    alter table(:latest_eth_wallet_data) do
      modify :tx_in, :real
      modify :tx_out, :real
      modify :balance, :real
      modify :last_incoming, :timestamp
      modify :last_outgoing, :timestamp
      modify :update_time, :timestamp
    end
  end

end
