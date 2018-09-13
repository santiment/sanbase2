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

  import Ecto.Query

  require Sanbase.ClickhouseRepo

  alias __MODULE__
  alias Sanbase.ClickhouseRepo

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

  # Private functions

  defp token_top_transfers_query(contract, from_datetime, to_datetime, limit, token_decimals) do
    from_datetime_unix = DateTime.to_unix(from_datetime)
    to_datetime_unix = DateTime.to_unix(to_datetime)

    query = """
    SELECT from, to, dt, transactionHash, any(value) / ?1 as value
    FROM #{@table}
    PREWHERE contract = ?2
    AND dt >= toDateTime(?3)
    AND dt <= toDateTime(?4)
    GROUP BY from, to, dt, transactionHash
    ORDER BY value desc
    LIMIT ?5
    """

    args = [
      token_decimals,
      contract,
      from_datetime,
      to_datetime_unix,
      limit
    ]

    {query, args}
  end
end
