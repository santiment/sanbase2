defmodule Sanbase.Clickhouse.BtcTransfers do
  @type transaction :: %{
          from_address: String.t(),
          to_address: String.t(),
          trx_value: float,
          trx_hash: String.t(),
          datetime: Datetime.t()
        }

  @spec top_transactions(%DateTime{}, %DateTime{}, non_neg_integer(), list()) ::
          {:ok, list(transaction)} | {:error, String.t()}
  def top_transactions(from, to, limit, excluded_addresses \\ []) do
    {query, args} = top_transactions_query(from, to, limit, excluded_addresses)

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

  defp top_transactions_query(from, to, limit, excluded_addresses) do
    to_unix = DateTime.to_unix(to)
    from_unix = DateTime.to_unix(from)

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
    LIMIT ?4
    """

    args =
      [amount_filter, from_unix, to_unix, limit] ++
        if excluded_addresses == [], do: [], else: [excluded_addresses]

    {query, args}
  end

  defp maybe_exclude_addresses([], _opts), do: ""

  defp maybe_exclude_addresses([_ | _], opts) do
    arg_position = Keyword.get(opts, :arg_position)

    "AND (from NOT IN (?#{arg_position}) AND to NOT IN (?#{arg_position}))"
  end
end
