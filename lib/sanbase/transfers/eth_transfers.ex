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
          :in | :out | :all
        ) ::
          {:ok, nil} | {:ok, list(map())} | {:error, String.t()}
  def top_wallet_transfers([], _from, _to, _page, _page_size, _type), do: {:ok, []}

  def top_wallet_transfers(wallets, from, to, page, page_size, type) do
    opts = [page: page, page_size: page_size]
    {query, args} = top_wallet_transfers_query(wallets, from, to, type, opts)

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
    opts = [page: page, page_size: page_size]
    {query, args} = top_transfers_query(from, to, opts)

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
          trx_value: trx_value
        }
    end)
  end

  def incoming_transfers_summary(address, from, to, opts \\ []) do
    execute_transfers_summary_query(:incoming, address, from, to, opts)
  end

  def outgoing_transfers_summary(address, from, to, opts \\ []) do
    execute_transfers_summary_query(:outgoing, address, from, to, opts)
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

  defp execute_transfers_summary_query(type, address, from, to, opts) do
    {query, args} = transfers_summary_query(type, address, from, to, opts)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [last_transfer_datetime, address, transaction_volumes, transfers_count] ->
        %{
          last_transfer_datetime: DateTime.from_unix!(last_transfer_datetime),
          address: address,
          transaction_volume: transaction_volumes,
          transfers_count: transfers_count
        }
      end
    )
  end

  defp top_wallet_transfers_query(wallets, from, to, type, opts) do
    query = """
    SELECT toUnixTimestamp(dt), from, to, transactionHash, (any(value) / #{@eth_decimals}) AS value
    FROM #{@table}
    PREWHERE
      #{top_wallet_transfers_address_clause(type, arg_position: 1, trailing_and: true)}
      dt >= toDateTime(?2) AND
      dt < toDateTime(?3) AND
      type = 'call'
    GROUP BY from, type, to, dt, transactionHash, primaryKey
    ORDER BY value DESC
    LIMIT ?4 OFFSET ?5
    """

    {limit, offset} = opts_to_limit_offset(opts)

    args = [
      wallets,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      limit,
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

  defp top_transfers_query(from, to, opts) do
    query = """
    SELECT toUnixTimestamp(dt), from, to, transactionHash, any(value) / #{@eth_decimals}
    FROM (
      SELECT dt, from, to, transactionHash, primaryKey, value
      FROM #{@table}
      PREWHERE
        type = 'call' AND
        dt >= toDateTime(?2) AND
        dt < toDateTime(?3)
        WHERE value > ?1 * #{@eth_decimals}
    )
    GROUP BY from, type, to, dt, transactionHash, primaryKey
    ORDER BY value DESC
    LIMIT ?4 OFFSET ?5
    """

    # only > 10K ETH transfers if range is > 1 week, otherwise only bigger than 1K
    value_filter = if Timex.diff(to, from, :days) > 7, do: 10_000, else: 1_000
    {limit, offset} = opts_to_limit_offset(opts)

    args = [
      value_filter,
      DateTime.to_unix(from),
      DateTime.to_unix(to),
      limit,
      offset
    ]

    {query, args}
  end

  defp recent_transactions_query(address, opts) do
    {limit, offset} = opts_to_limit_offset(opts)
    only_sender = Keyword.get(opts, :only_sender, false)

    query = """
    SELECT toUnixTimestamp(dt), from, to, transactionHash, (value / #{@eth_decimals}) AS value
    FROM (
      SELECT dt, from, to, transactionHash, any(value) AS value
      FROM eth_transfers
      PREWHERE
        #{if only_sender, do: "from = ?1", else: "(from = ?1 OR to = ?1)"} AND
        type = 'call'
      GROUP BY from, type, to, dt, transactionHash, primaryKey
    )
    ORDER BY dt DESC
    LIMIT ?2 OFFSET ?3
    """

    address = Sanbase.BlockchainAddress.to_internal_format(address)
    args = [address, limit, offset]

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
      SELECT dt, 0 AS incoming, any(value) AS outgoing
      FROM eth_transfers
      PREWHERE
        from IN (?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY dt, from, to, transactionHash, primaryKey

      UNION ALL

      SELECT dt, any(value) AS incoming, 0 AS outgoing
      FROM eth_transfers_to
      PREWHERE
        to in (?2) AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY dt, from, to, transactionHash, primaryKey
    )
    GROUP BY time
    """

    from = DateTime.to_unix(from)
    to = DateTime.to_unix(to)
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    args = [interval_sec, addresses, from, to]

    {query, args}
  end

  defp transfers_summary_query(type, address, from, to, opts) do
    order_by_str =
      case Keyword.get(opts, :order_by, :transaction_volume) do
        :transaction_volume -> "transaction_volume"
        :transfers_count -> "transfers_count"
      end

    {limit, offset} = opts_to_limit_offset(opts)

    {select_column, filter_column, table} =
      case type do
        :incoming -> {"from", "to", "eth_transfers_to"}
        :outgoing -> {"to", "from", "eth_transfers"}
      end

    query = """
    SELECT
      toUnixTimestamp(max(dt)) AS last_transfer_datetime,
      "#{select_column}" AS address,
      SUM(value) / pow(10,18) AS transaction_volume,
      COUNT(*) AS transfers_count
    FROM (
      SELECT dt, type, from, to, anyLast(value) AS value
      FROM #{table}
      PREWHERE #{filter_column} = ?1 AND type != 'fee' AND dt >= toDateTime(?2) AND dt < toDateTime(?3)
      GROUP BY from, type, to, dt, transactionHash, primaryKey
    )
    GROUP BY "#{select_column}"
    ORDER BY #{order_by_str} DESC
    LIMIT ?4 OFFSET ?5
    """

    args = [address, from, to, limit, offset]

    {query, args}
  end
end
