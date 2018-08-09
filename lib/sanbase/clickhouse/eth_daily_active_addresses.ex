defmodule Sanbase.Clickhouse.EthDailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for ETH

  Note: Experimental. Define the schema but do not use it now.
  """

  use Ecto.Schema

  import Ecto.Query

  alias __MODULE__
  alias Sanbase.ClickhouseRepo

  @timestamps_opts updated_at: false
  @primary_key false
  schema "eth_daily_active_addresses" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:address, :string, primary_key: true)
    field(:total_transactions, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end
end
