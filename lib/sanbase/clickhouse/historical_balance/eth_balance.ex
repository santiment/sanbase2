defmodule Sanbase.Clickhouse.HistoricalBalance.EthBalance do
  @doc ~s"""
  Returns the historical balances of given ethereum address in all intervals between two datetimes.
  """

  use Ecto.Schema

  import Sanbase.Clickhouse.HistoricalBalance.Utils

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @eth_decimals 1_000_000_000_000_000_000
  @type historical_balance :: %{
          datetime: non_neg_integer(),
          balance: float
        }

  @table "eth_balances"
  schema @table do
    field(:datetime, :utc_datetime, source: :dt)
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
        result =
          result
          |> fill_gaps_last_seen_balance()
          |> Enum.drop_while(fn %{datetime: dt} -> DateTime.compare(dt, from) == :lt end)

        {:ok, result}

      error ->
        error
    end
  end

  @first_datetime ~N[2015-07-29 00:00:00]
                  |> DateTime.from_naive!("Etc/UTC")
                  |> DateTime.to_unix()
  defp historical_balance_query(address, from, to, interval) do
    interval = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    span = div(to_unix - @first_datetime, interval) |> max(1) |> IO.inspect(label: "SPAN")

    # The balances table is like a stack. For each balance change there is a record
    # with sign = -1 that is the old balance and with sign = 1 which is the new balance
    query = """
    SELECT time, SUM(value), toInt32(SUM(sign))
      FROM (
        SELECT
          toDateTime(intDiv(toUInt32(?4 + number * ?1), ?1) * ?1) AS time,
          toFloat64(0) AS value,
          toInt32(0) AS sign
        FROM numbers(?2)

    UNION ALL

    SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) AS time, argMax(value, dt), toInt32(1) AS sign
      FROM #{@table}
      PREWHERE address = ?3
      AND sign = 1
      AND dt <= toDateTime(?5)
      GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      span,
      address,
      @first_datetime,
      to_unix
    ]

    {query, args}
  end
end
