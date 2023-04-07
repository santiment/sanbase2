defmodule Sanbase.Transfers.BtcTransfers do
  alias Sanbase.ClickhouseRepo

  @type transaction :: %{
          from_address: String.t(),
          to_address: String.t(),
          trx_value: float,
          trx_hash: String.t(),
          datetime: Datetime.t()
        }

  @spec top_transfers(
          %DateTime{},
          %DateTime{},
          non_neg_integer(),
          non_neg_integer(),
          list(String.t())
        ) ::
          {:ok, list(transaction)} | {:error, String.t()}
  def top_transfers(from, to, page, page_size, excluded_addresses \\ []) do
    query_struct = top_transfers_query(from, to, page, page_size, excluded_addresses)

    Sanbase.ClickhouseRepo.query_transform(
      query_struct,
      fn [dt, to_address, value, trx_id] ->
        %{
          datetime: DateTime.from_unix!(dt),
          to_address: to_address,
          from_address: nil,
          trx_hash: trx_id,
          trx_value: value
        }
      end
    )
  end

  @spec top_wallet_transfers(
          list(String.t()),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer,
          non_neg_integer,
          :in | :out | :all
        ) ::
          {:ok, nil} | {:ok, list(map())} | {:error, String.t()}
  def top_wallet_transfers([], _from, _to, _page, _page_size, _type),
    do: {:ok, []}

  def top_wallet_transfers(wallets, from, to, page, page_size, type) do
    query_struct = top_wallet_transfers_query(wallets, from, to, page, page_size, type)

    ClickhouseRepo.query_transform(query_struct, fn
      [timestamp, address, trx_hash, balance, old_balance, abs_value] ->
        # if the new balance is bigger then the address is the receiver
        {from_address, to_address} =
          case balance > old_balance do
            true -> {nil, address}
            false -> {address, nil}
          end

        %{
          datetime: DateTime.from_unix!(timestamp),
          from_address: from_address,
          to_address: to_address,
          trx_hash: trx_hash,
          trx_value: abs_value
        }
    end)
  end

  # Private functions

  defp top_wallet_transfers_query(wallets, from, to, page, page_size, type) do
    sql = """
    SELECT
      toUnixTimestamp(dt),
      address,
      any(txID) AS txID,
      any(balance) AS balance,
      any(oldBalance) AS oldBalance,
      any(absValue) AS absValue
    FROM (
      SELECT dt, address, txID, blockNumber, txPos, balance, oldBalance, balance - oldBalance AS absValue
      FROM btc_balances
      WHERE
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}}) AND
        #{top_wallet_transfers_address_clause(type, argument_name: "wallets", trailing_and: false)}
    )
    GROUP BY dt, address, blockNumber, txPos
    ORDER BY absValue DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} =
      Sanbase.Utils.Transform.opts_to_limit_offset(page: page, page_size: page_size)

    params = %{
      wallets: wallets,
      from: DateTime.to_unix(from),
      to: DateTime.to_unix(to),
      limit: limit,
      offset: offset
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp top_wallet_transfers_address_clause(:in, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "address IN ({{#{arg_name}}}) AND balance > oldBalance"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:out, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "address IN ({{#{arg_name}}}) AND balance < oldBalance"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:all, opts) do
    arg_name = Keyword.fetch!(opts, :argument_name)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = """
    address IN ({{#{arg_name}}})
    """

    if trailing_and, do: str <> " AND", else: str
  end

  defp top_transfers_query(from, to, page, page_size, excluded_addresses) do
    sql = """
    SELECT
      toUnixTimestamp(dt),
      address,
      any(amount) AS amount,
      any(txID) AS txID
    FROM (
      SELECT dt, address, blockNumber, txPos, txID,  balance, oldBalance, balance - oldBalance AS amount
      FROM btc_balances
      PREWHERE
        amount >= {{amount_filter}} AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
        #{maybe_exclude_addresses(excluded_addresses, argument_name: "excluded_addresses")}
    )
    GROUP BY dt, address, blockNumber, txPos
    ORDER BY amount DESC
    LIMIT {{limit}} OFFSET {{offset}}
    """

    {limit, offset} =
      Sanbase.Utils.Transform.opts_to_limit_offset(page: page, page_size: page_size)

    # only > 100 BTC transfers if range is > 1 week, otherwise only bigger than 20
    amount_filter = if Timex.diff(to, from, :days) > 7, do: 100, else: 20

    params = %{
      amount_filter: amount_filter,
      from: DateTime.from_unix(from),
      to: DateTime.from_unix(to),
      limit: limit,
      offset: offset,
      excluded_addresses: excluded_addresses
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_name = Keyword.get(opts, :argument_name)

    "AND (from NOT IN ({{#{arg_name}}}) AND to NOT IN ({{#{arg_name}}}))"
  end
end
