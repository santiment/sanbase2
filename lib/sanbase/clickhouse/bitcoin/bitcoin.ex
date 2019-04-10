defmodule Sanbase.Clickhouse.Bitcoin do
  @moduledoc ~s"""
  Fetch all bitcoin metrics from a table that contains daily metrics.
  """
  use Ecto.Schema
  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @aggregations [:sum, :avg]
  @metrics [
    :average_price_usd,
    :average_marketcap_usd,
    :daily_stack_circulation,
    :stack_age_consumed,
    :stack_realized_value_usd,
    :transaction_volume,
    :active_addresses
  ]
  @table "btc_daily_metrics"
  schema @table do
    field(:dt, :utc_datetime)
    field(:average_price_usd, :float)
    field(:average_marketcap_usd, :float)
    field(:daily_stack_circulation, :float)
    field(:stack_age_consumed, :float)
    field(:stack_realized_value_usd, :float)
    field(:transaction_volume, :float)
    field(:active_addresses, :integer)
  end

  def changeset(_, _attrs \\ %{}) do
    raise "Should not try to change Clickhouse bitcoin metrics"
  end

  def daily_active_addresses(from, to, interval) do
    get_simple_metric(:active_addresses, :active_addresses, :avg, from, to, interval)
  end

  def token_age_consumed(from, to, interval) do
    get_simple_metric(:stack_age_consumed, :token_age_consumed, :avg, from, to, interval)
  end

  def transaction_volume(from, to, interval) do
    get_simple_metric(:transaction_volume, :transaction_volume, :sum, from, to, interval)
  end

  def token_circulation(from, to, interval) do
    get_simple_metric(:daily_stack_circulation, :token_circulation, :avg, from, to, interval)
  end

  def token_velocity(from, to, interval) do
    {query, args} = token_velocity_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, value] ->
        %{
          token_velocity: value,
          datetime: DateTime.from_unix!(dt)
        }
      end
    )
  end

  def mvrv_ratio(from, to, interval) do
    {query, args} = mvrv_ratio_query(from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, value] ->
        %{
          ratio: value,
          datetime: DateTime.from_unix!(dt)
        }
      end
    )
  end

  # Generic way to fetch a metric that is used by making an aggregation over
  # one field. Example for such metrics are:
  # - Daily Active Addresses by taking the average
  # - Transaction Volume by taking the sum
  # - Token Age Consumed by taking the sum
  # - Token Circulation by taking the avg
  defp get_simple_metric(metric, metric_name, aggregation, from, to, interval)
       when metric in @metrics and aggregation in @aggregations do
    {query, args} = get_simple_metric_query(metric, aggregation, from, to, interval)

    ClickhouseRepo.query_transform(
      query,
      args,
      fn [dt, value] ->
        %{
          metric_name => value,
          datetime: DateTime.from_unix!(dt)
        }
      end
    )
  end

  defp get_simple_metric_query(metric, aggregation, from, to, interval) do
    interval_seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
    toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
      #{aggregation}(#{metric}) as metric
    FROM #{@table}
    PREWHERE
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    GROUP BY time
    ORDER BY time
    """

    args = [interval_seconds, DateTime.to_unix(from), DateTime.to_unix(to)]

    {query, args}
  end

  defp mvrv_ratio_query(from, to, interval) do
    interval_seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
    toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
      avg(average_marketcap_usd) / avg(stack_realized_value_usd) as value
    FROM #{@table}
    PREWHERE
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    GROUP BY time
    ORDER BY time
    """

    args = [interval_seconds, DateTime.to_unix(from), DateTime.to_unix(to)]

    {query, args}
  end

  defp token_velocity_query(from, to, interval \\ 86400) do
    interval_seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)

    query = """
    SELECT
    toUnixTimestamp((intDiv(toUInt32(toDateTime(dt)), ?1) * ?1)) AS time,
      avg(transaction_volume) / avg(daily_stack_circulation) as value
    FROM #{@table}
    PREWHERE
      dt >= toDateTime(?2) AND
      dt <= toDateTime(?3)
    GROUP BY time
    ORDER BY time
    """

    args = [interval_seconds, DateTime.to_unix(from), DateTime.to_unix(to)]

    {query, args}
  end
end
