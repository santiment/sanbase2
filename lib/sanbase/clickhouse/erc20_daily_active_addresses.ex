defmodule Sanbase.Clickhouse.Erc20DailyActiveAddresses do
  @moduledoc ~s"""
  Uses ClickHouse to calculate the daily active addresses for an ERC20 token
  """

  use Ecto.Schema

  import Ecto.Query
  import Sanbase.Clickhouse.EctoFunctions

  alias Sanbase.ClickhouseRepo
  alias __MODULE__

  @primary_key false
  @timestamps_opts updated_at: false
  schema "erc20_daily_active_addresses" do
    field(:dt, :utc_datetime, primary_key: true)
    field(:contract, :string, primary_key: true)
    field(:address, :string, primary_key: true)
    field(:total_transactions, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  def count_erc20_daa(contract, from_datetime, to_datetime) do
    from(
      daa in Erc20DailyActiveAddresses,
      where: daa.contract == ^contract and daa.dt > ^from_datetime and daa.dt < ^to_datetime,
      group_by: daa.dt,
      order_by: daa.dt,
      select: {daa.dt, count("*")}
    )
    |> query_all_use_prewhere()
  end
end
