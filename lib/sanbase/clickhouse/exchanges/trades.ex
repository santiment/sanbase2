defmodule Sanbase.Clickhouse.Exchanges.Trades do
  use Ecto.Schema

  @exchanges ["Binance", "Bitfinex", "Kraken", "Poloniex", "Bitrex"]

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @table "exchange_trades"
  schema @table do
    field(:source, :string)
    field(:symbol, :string)
    field(:timestamp, :utc_datetime)
    field(:side, :string)
    field(:amount, :float)
    field(:price, :float)
    field(:cost, :float)
  end

  @doc false
  @spec changeset(any(), any()) :: no_return()
  def changeset(_, _),
    do: raise("Should not try to change exchange trades")

  def exchange_trades(exchange, ticker_pair, from, to) when exchange in @exchanges do
    {query, args} = exchange_trades_query(exchange, ticker_pair, from, to)

    ClickhouseRepo.query_transform(query, args, fn
      [source, symbol, timestamp, side, amount, price, cost] ->
        %{
          source: source,
          symbol: symbol,
          timestamp: timestamp |> Sanbase.DateTimeUtils.from_erl!(),
          amount: amount,
          side: side,
          price: price,
          cost: cost
        }
    end)
  end

  def exchange_trades(exchange, ticker_pair, from, to, interval) when exchange in @exchanges do
    {query, args} = exchange_trades_aggregated_query(exchange, ticker_pair, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn
      [source, symbol, timestamp, amount, cost, price] ->
        %{
          source: source,
          symbol: symbol,
          timestamp: timestamp |> Sanbase.DateTimeUtils.from_erl!(),
          amount: amount,
          cost: cost,
          price: price
        }
    end)
  end

  defp exchange_trades_query(exchange, ticker_pair, from, to) do
    query = """
    SELECT
      source, symbol, dt, side, amount, price, cost
    FROM #{@table}
    PREWHERE
      source == ?1 AND symbol == ?2 AND
      dt >= toDateTime(?3) AND
      dt <= toDateTime(?4)
    ORDER BY dt
    """

    args = [
      exchange,
      ticker_pair,
      from |> DateTime.to_unix(),
      to |> DateTime.to_unix()
    ]

    {query, args}
  end

  defp exchange_trades_aggregated_query(exchange, ticker_pair, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)
    from_datetime_unix = DateTime.to_unix(from)
    to_datetime_unix = DateTime.to_unix(to)
    span = div(to_datetime_unix - from_datetime_unix, interval) |> max(1)

    query = """
    SELECT time, any(total_amount), any(total_cost), any(avg_price)
    FROM (
      SELECT
        toDateTime(intDiv(toUInt32(?5 + number * ?1), ?1) * ?1) as time,
        0 AS total_amount,
        0 AS total_cost,
        0 AS avg_price
      FROM numbers(?2)

      UNION ALL

      SELECT toDateTime(intDiv(toUInt32(dt), ?1) * ?1) as time,
        any(total_amount),
        any(total_cost),
        any(avg_price)
        FROM (
          SELECT
            source, symbol, dt,
            sum(amount) as total_amount,
            sum(cost) as total_cost,
            avg(price) as avg_price
          FROM exchange_trades
          PREWHERE
            source == ?3 AND symbol == ?4 AND
            dt >= toDateTime(?5) AND
            dt <= toDateTime(?6)
          GROUP BY source, symbol, dt
        )
        GROUP BY time
    )
    GROUP BY time
    ORDER BY time
    """

    args = [
      interval,
      span,
      exchange,
      ticker_pair,
      from_datetime_unix,
      to_datetime_unix
    ]

    {query, args}
  end
end
