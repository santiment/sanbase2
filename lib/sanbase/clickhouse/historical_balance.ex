defmodule Sanbase.Clickhouse.HistoricalBalance.EthBalance do
  @doc ~s"""
  Returns the historical balances of given ethereum address in all intervals between two datetimes.
  """

  use Ecto.Schema

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000
  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float
        }

  @table "eth_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
    field(:contract, :string)
    field(:address, :string, source: :to)
    field(:value, :float)
    field(:sign, :integer)
  end

  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _attrs \\ %{}),
    do: raise("Should not try to change eth daily active addresses")

  @spec historical_balance(
          String.t(),
          DateTime.t(),
          DateTime.t(),
          non_neg_integer()
        ) :: {:ok, list(historical_balance)}
  def historical_balance(address, from, to, interval) do
    {query, args} =
      String.downcase(address)
      |> historical_balance_query(from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [dt, value, sign] ->
      %{datetime: Sanbase.DateTimeUtils.from_erl!(dt), balance: value / @eth_decimals, sign: sign}
    end)
    |> case do
      {:ok, result} ->
        # Clickhouse fills empty buckets with 0 while we need it filled with the last
        # seen value. As the balance changes happen only when a transfer occurs
        # then we need to fetch the whole history of changes in order to find the balance
        result =
          result
          |> Enum.reduce({0, []}, fn
            %{sign: 1, balance: balance, datetime: dt}, {_last_seen, acc} ->
              {balance, [%{balance: balance, datetime: dt} | acc]}

            %{sign: 0, datetime: dt}, {last_seen, acc} ->
              {last_seen, [%{balance: last_seen, datetime: dt} | acc]}
          end)
          |> elem(1)
          |> Enum.reverse()
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      error ->
        error
    end
  end

  @hardcoded_eth_from_unix ~N[2014-05-13 00:00:00]
                           |> DateTime.from_naive!("Etc/UTC")
                           |> DateTime.to_unix()
  defp historical_balance_query(address, _from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - @hardcoded_eth_from_unix, interval) |> max(1)

    query = """
    SELECT time, SUM(value), toInt32(SUM(sign))
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) as time,
          toFloat64(0) AS value,
          toInt32(0) as sign
        FROM numbers(?2)

        UNION ALL

    SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time, argMax(value, dt), argMax(sign, dt)
      FROM (
        SELECT any(value) as value, dt, 1 as sign
        FROM #{@table}
        PREWHERE address = ?3
        AND sign = 1
        AND dt >= toDateTime(?4)
        AND dt <= toDateTime(?5)
        GROUP BY address, dt
      )
      GROUP BY time
      ORDER BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      span,
      address,
      @hardcoded_eth_from_unix,
      to_unix
    ]

    # args = [interval, address, from_unix, to_unix]

    {query, args}
  end
end
