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
    {query, args} = top_transfers_query(from, to, page, page_size, excluded_addresses)

    Sanbase.ClickhouseRepo.query_transform(
      query,
      args,
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
  def top_wallet_transfers([], _from, _to, _page, _page_size, _type), do: {:ok, []}

  def top_wallet_transfers(wallets, from, to, page, page_size, type) do
    {query, args} = top_wallet_transfers_query(wallets, from, to, page, page_size, type)

    ClickhouseRepo.query_transform(query, args, fn
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
    query = """
    SELECT
      toUnixTimestamp(dt),
      address,
      txID,
      balance,
      oldBalance,
      abs(balance - oldBalance) AS absValue
    FROM btc_balances FINAL
    PREWHERE
      #{top_wallet_transfers_address_clause(type, arg_position: 1, trailing_and: true)}
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    ORDER BY absValue DESC
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

    str = "address IN (?#{arg_position}) AND balance > oldBalance"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:out, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = "address IN (?#{arg_position}) AND balance < oldBalance"
    if trailing_and, do: str <> " AND", else: str
  end

  defp top_wallet_transfers_address_clause(:all, opts) do
    arg_position = Keyword.fetch!(opts, :arg_position)
    trailing_and = Keyword.fetch!(opts, :trailing_and)

    str = """
    address IN (?#{arg_position})
    """

    if trailing_and, do: str <> " AND", else: str
  end

  defp top_transfers_query(from, to, page, page_size, excluded_addresses) do
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)
    offset = (page - 1) * page_size
    # only > 100 BTC transfers if range is > 1 week, otherwise only bigger than 20
    amount_filter = if Timex.diff(to, from, :days) > 7, do: 100, else: 20

    query = """
    SELECT
      toUnixTimestamp(dt),
      address,
      balance - oldBalance AS amount,
      txID
    FROM btc_balances FINAL
    PREWHERE
      amount > ?1 AND
      dt >= toDateTime(?2) AND
      dt < toDateTime(?3)
      #{maybe_exclude_addresses(excluded_addresses, arg_position: 5)}
    ORDER BY amount DESC
    LIMIT ?4 OFFSET ?5
    """

    args =
      [amount_filter, from_unix, to_unix, page_size, offset] ++
        if excluded_addresses == [], do: [], else: [excluded_addresses]

    {query, args}
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_position = Keyword.get(opts, :arg_position)

    "AND (from NOT IN (?#{arg_position}) AND to NOT IN (?#{arg_position}))"
  end
end
