defmodule Sanbase.Clickhouse.Erc20TransactionVolume do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the transaction volume for an ERC20 token

  Note: Experimental. Define the schema but do not use it now.
  """
  use Ecto.Schema

  @primary_key false
  @timestamps_opts updated_at: false
  schema "erc20_transaction_volume" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:contract, :string, primary_key: true)
    field(:value, :string, primary_key: true)
    field(:total_transactions, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end
end
