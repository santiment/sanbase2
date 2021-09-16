defmodule Sanbase.Transfers.EthTransfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ETH transfers.
  """

  use Ecto.Schema

  import Sanbase.Utils.Transform

  alias Sanbase.ClickhouseRepo

  require Logger

  @type t :: %__MODULE__{
          datetime: %DateTime{},
          from_address: String.t(),
          to_address: String.t(),
          trx_hash: String.t(),
          trx_value: float,
          block_number: non_neg_integer,
          trx_position: non_neg_integer,
          type: String.t()
        }

  @type wallets :: list(String.t())

  @table "eth_transfers"
  @eth_decimals 1_000_000_000_000_000_000

  @primary_key false
  @timestamps_opts [updated_at: false]
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:from_address, :string, primary_key: true, source: :from)
    field(:to_address, :string, primary_key: true, source: :to)
    field(:trx_hash, :string, source: :transactionHash)
    field(:trx_value, :float, source: :value)
    field(:block_number, :integer, source: :blockNumber)
    field(:trx_position, :integer, source: :transactionPosition)
    field(:type, :string)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _) do
    raise "Should not try to change eth transfers"
  end

  @doc ~s"""
  Return the biggest transfers for a list of wallets and time period.

  The `type` argument control wheteher only incoming, outgoing or all transactions
  are included.
  """
  @spec top_wallet_transfers(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer,
          non_neg_integer,
          String.t()
        ) ::
          {:ok, nil} | {:ok, list(map())} | {:error, String.t()}
  def top_wallet_transfers([], _from, _to, _page, _page_size, _type), do: {:ok, []}

  def top_wallet_transfers(wallets, from, to, page, page_size, type) do
    {query, args} = top_wallet_transfers_query(wallets, from, to, page, page_size, type)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: maybe_transform_from_address(from_address),
          to_address: maybe_transform_to_address(to_address),
          trx_hash: trx_hash,
          trx_value: trx_value
        }
    end)
  end

  @spec top_transfers(%DateTime{}, %DateTime{}, non_neg_integer(), non_neg_integer()) ::
          {:ok, list(t)} | {:error, String.t()}
  def top_transfers(from, to, page, page_size) do
    {query, args} = top_transfers_query(from, to, page, page_size)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: maybe_transform_from_address(from_address),
          to_address: maybe_transform_to_address(to_address),
          trx_hash: trx_hash,
          trx_value: trx_value / @eth_decimals
        }
    end)
  end

  @spec recent_transactions(String.t(),
          page: non_neg_integer(),
          page_size: non_neg_integer(),
          only_sender: boolean()
        ) ::
          {:ok, nil} | {:ok, list(t)} | {:error, String.t()}
  def recent_transactions(address, opts) do
    {query, args} = recent_transactions_query(address, opts)

    ClickhouseRepo.query_transform(query, args, fn
      [timestamp, from_address, to_address, trx_hash, trx_value] ->
        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: from_address,
          to_address: to_address,
          trx_hash: trx_hash,
          trx_value: trx_value / @eth_decimals
        }
    end)
  end

  def blockchain_address_transaction_volume_over_time(addresses, from, to, interval) do
  end

  # Private functions

  defp top_wallet_transfers_query(wallets, from, to, page, page_size, type) do
    query = """
    SELECT
      toUnixTimestamp(dt),
      from,
      to,
      transactionHash,
      value / #{@eth_decimals}
    FROM #{@table} FINAL
    PREWHERE
      #{top_wallet_transfers_address_clause(type, arg_position: 1, trailing_and: true)}
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3) AND
      type = 'call'
    ORDER BY value DESC
    LIMIT ?4 OFFSET ?5
    """

    offset = (page - 1) * page_size

    args = [
      wallets,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix(),
      page_size,
      offset
    ]

    {query, args}
  end

  defp top_wallet_transfers_address_clause(:in, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from NOT IN (?#{arg_position}) AND to IN (?#{arg_position})"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:out, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "from IN (?#{arg_position}) AND to NOT IN (?#{arg_position})"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:all, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = """
    (
      (from IN (?#{arg_position}) AND NOT to IN (?#{arg_position})) OR
      (NOT from IN (?#{arg_position}) AND to IN (?#{arg_position}))
    )
    """

    if trailing_and, do: str <> " AND", else: str
  end

  defp top_transfers_query(from, to, page, page_size) do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)

    # only > 10K ETH transfers if range is > 1 week, otherwise only bigger than 1K
    value_filter = if Timex.diff(to, from, :days) > 7, do: 10_000, else: 1_000
    offset = (page - 1) * page_size

    query = """
    SELECT
      toUnixTimestamp(dt), from, to, transactionHash, value
    FROM #{@table} FINAL
    PREWHERE
      value > ?1 AND
      type = 'call' AND
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    ORDER BY value DESC
    LIMIT ?4 OFFSET ?5
    """

    args = [
      value_filter,
      from_unix,
      to_unix,
      page_size,
      offset
    ]

    {query, args}
  end

  defp recent_transactions_query(address, opts) do
    page = Keyword.get(opts, :page, 1)
    page_size = Keyword.get(opts, :page_size, 10)
    only_sender = Keyword.get(opts, :only_sender, false)
    offset = (page - 1) * page_size

    query = """
    SELECT
      toUnixTimestamp(dt), from, to, transactionHash, value
    FROM eth_transfers FINAL
    PREWHERE
      #{if only_sender, do: "from = ?1", else: "(from = ?1 OR to = ?1)"} AND
      type = 'call'
    ORDER BY dt DESC
    LIMIT ?2 OFFSET ?3
    """

    args = [String.downcase(address), page_size, offset]

    {query, args}
  end
end
