defmodule Sanbase.Clickhouse.Erc20Transfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ERC20 transfers.
  """

  @type t :: %__MODULE__{
          datetime: %DateTime{},
          contract: String.t(),
          from_address: String.t(),
          to_address: String.t(),
          trx_hash: String.t(),
          trx_value: float,
          block_number: non_neg_integer,
          trx_position: non_neg_integer,
          log_index: non_neg_integer
        }

  use Ecto.Schema

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  alias Sanbase.Clickhouse.Common, as: ClickhouseCommon

  @table "erc20_transfers"

  @primary_key false
  @timestamps_opts updated_at: false
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string, primary_key: true)
    field(:from_address, :string, primary_key: true, source: :from)
    field(:to_address, :string, primary_key: true, source: :to)
    field(:trx_hash, :string, source: :transactionHash)
    field(:trx_value, :float, source: :value)
    field(:block_number, :integer, source: :blockNumber)
    field(:trx_position, :integer, source: :transactionPosition)
    field(:log_index, :integer, source: :logIndex)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change eth daily active addresses"
  end

  @doc ~s"""
  Return the `limit` biggest transaction for a given contract and time period.
  If the top transactions for SAN token are needed, the SAN contract address must be
  provided as a first argument.
  """
  @spec token_top_transfers(String.t(), %DateTime{}, %DateTime{}, String.t(), integer) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def token_top_transfers(contract, from_datetime, to_datetime, limit, token_decimals \\ 0) do
    token_decimals = Sanbase.Utils.Math.ipow(10, token_decimals)

    {query, args} =
      token_top_transfers_query(contract, from_datetime, to_datetime, limit, token_decimals)

    ClickhouseRepo.query_transform(query, args)
  end

  @doc ~s"""
  Returns the historical balances of given address in tokens in all intervals between two datetimes.
  """
  def historical_balance(
        contract,
        address,
        from_datetime,
        to_datetime,
        interval,
        token_decimals \\ 0
      ) do
    token_decimals = Sanbase.Utils.Math.ipow(10, token_decimals)

    address = String.downcase(address)
    {query, args} = historical_balance_query(contract, address, interval, token_decimals)

    balances =
      query
      |> ClickhouseRepo.query_transform(args, fn [dt, value] -> {dt, value} end)
      |> ClickhouseCommon.convert_historical_balance_result(from_datetime, to_datetime, interval)

    {:ok, balances}
  end

  # Private functions

  defp historical_balance_query(contract, address, interval, token_decimals) do
    args = [contract, address]

    dt_round = ClickhouseCommon.datetime_rounding_for_interval(interval)

    query = """
    SELECT dt, runningAccumulate(state) AS total_balance FROM (
      SELECT dt, sumState(value) AS state FROM (
        SELECT
          toUnixTimestamp(#{dt_round}) as dt, from AS address, sum(-value / #{token_decimals}) AS value
        FROM #{@table}
        PREWHERE contract = ?1 AND from = ?2
        GROUP BY dt, address

        UNION ALL

        SELECT
          toUnixTimestamp(#{dt_round}) AS dt, to AS address, sum(value / #{token_decimals}) AS value
        FROM #{@table}
        PREWHERE contract = ?1 AND to = ?2
        GROUP BY dt, address
      )
      GROUP BY dt
      ORDER BY dt
    )
    ORDER BY dt
    """

    {query, args}
  end

  defp token_top_transfers_query(contract, from_datetime, to_datetime, limit, token_decimals) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

    query = """
    SELECT contract, from, to, dt, transactionHash, any(value) / ?1 as value
    FROM #{@table}
    PREWHERE contract = ?2
    AND dt >= toDateTime(?3)
    AND dt <= toDateTime(?4)
    GROUP BY contract, from, to, dt, transactionHash, logIndex
    ORDER BY value desc
    LIMIT ?5
    """

    args = [
      token_decimals,
      contract,
      from_datetime_unix,
      to_datetime_unix,
      limit
    ]

    {query, args}
  end
end
