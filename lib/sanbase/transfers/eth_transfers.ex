defmodule Sanbase.Transfers.EthTransfers do
  @moduledoc ~s"""
  Uses ClickHouse to work with ETH transfers.
  """

  import Sanbase.Utils.Transform

  alias Sanbase.ClickhouseRepo

  require Logger

  @type wallets :: list(String.t())

  @table "eth_transfers"
  @eth_decimals 1_000_000_000_000_000_000

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
          {:ok, list(map())} | {:error, String.t()}
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
          {:ok, nil} | {:ok, list(map)} | {:error, String.t()}
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

  def incoming_transfers_summary(address, from, to, limit, opts \\ []) do
    {query, args} = incoming_transfers_summary_query(address, from, to, limit, opts)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [address, total, transfers_count] ->
        %{address: address, total: total, transfers_count: transfers_count}
      end
    )
  end

  def outgoing_transfers_summary(address, from, to, limit, opts \\ []) do
    {query, args} = outgoing_transfers_summary_query(address, from, to, limit, opts)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [address, total, transfers_count] ->
        %{address: address, total: total, transfers_count: transfers_count}
      end
    )
  end

  def blockchain_address_transaction_volume_over_time(addresses, from, to, interval) do
    {query, args} =
      blockchain_address_transaction_volume_over_time_query(addresses, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [unix, incoming, outgoing] ->
        %{
          datetime: DateTime.from_unix!(unix),
          transaction_volume_inflow: incoming,
          transaction_volume_outflow: outgoing,
          transaction_volume_total: incoming + outgoing
        }
      end
    )
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

  defp blockchain_address_transaction_volume_over_time_query(addresses, from, to, interval) do
    query = """
    WITH pow(10, 18) AS expanded_decimals
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS time,
      SUM(incoming) / expanded_decimals AS incoming,
      SUM(outgoing) / expanded_decimals AS outgoing
    FROM (
      SELECT
        dt,
        0 AS incoming,
        value AS outgoing
      FROM eth_transfers FINAL
      PREWHERE
        from IN (?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)

      UNION ALL

      SELECT
        dt,
        value AS incoming,
        0 AS outgoing
      FROM eth_transfers_to FINAL
      PREWHERE
        to in (?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
    )
    GROUP BY time
    """

    from = DateTime.to_unix(from)
    to = DateTime.to_unix(to)
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    args = [interval_sec, addresses, from, to]

    {query, args}
  end

  defp incoming_transfers_summary_query(address, from, to, limit, opts) do
    order_by_str =
      case Keyword.get(opts, :order_by, :transaction_volume) do
        :transaction_volume -> "transaction_volume"
        :transfers_count -> "transfers_count"
      end

    query = """
    SELECT
      "from" AS address,
      SUM(value) / pow(10,?1) AS transaction_volume,
      COUNT(*) AS transfers_count
    FROM eth_transfers_to
    PREWHERE to = ?2 AND type != 'fee' AND dt >= toDateTime(?3) AND dt < toDateTime(?4)
    GROUP BY "from"
    ORDER BY #{order_by_str} DESC
    LIMIT ?5
    """

    args = [_decimals = 18, address, from, to, limit]

    {query, args}
  end

  defp outgoing_transfers_summary_query(address, from, to, limit, opts) do
    order_by_str =
      case Keyword.get(opts, :order_by, :transaction_volume) do
        :transaction_volume -> "transaction_volume"
        :transfers_count -> "transfers_count"
      end

    query = """
    SELECT
      "to" AS address,
      SUM(value) / pow(10,?1) AS transaction_volume,
      COUNT(*) AS transfers_count
    FROM eth_transfers
    PREWHERE from = ?2 AND type != 'fee' AND dt >= toDateTime(?3) AND dt < toDateTime(?4)
    GROUP BY "to"
    ORDER BY #{order_by_str} DESC
    LIMIT ?5
    """

    args = [_decimals = 18, address, from, to, limit]

    {query, args}
  end
end
