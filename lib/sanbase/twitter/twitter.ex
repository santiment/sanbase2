defmodule Sanbase.Twitter do
  @table "twitter_followers"

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  def timeseries_data(twitter_handle, from, to, interval) do
    timeseries_data_query(twitter_handle, from, to, interval)
    |> Sanbase.ClickhouseRepo.query_transform(fn [dt, value] ->
      %{
        datetime: DateTime.from_unix!(dt),
        value: value
      }
    end)
  end

  def last_record(twitter_handle) do
    last_record_query(twitter_handle)
    |> Sanbase.ClickhouseRepo.query_transform(fn [dt, value] ->
      %{
        datetime: DateTime.from_unix!(dt),
        followers_count: value
      }
    end)
    |> maybe_unwrap_ok_value()
  end

  def first_datetime(twitter_handle) do
    first_datetime_query(twitter_handle)
    |> Sanbase.ClickhouseRepo.query_transform(fn [ts] -> DateTime.from_unix!(ts) end)
    |> maybe_unwrap_ok_value()
  end

  def last_datetime(twitter_handle) do
    last_datetime_query(twitter_handle)
    |> Sanbase.ClickhouseRepo.query_transform(fn [ts] -> DateTime.from_unix!(ts) end)
    |> maybe_unwrap_ok_value()
  end

  # private

  defp timeseries_data_query(twitter_handle, from, to, interval) do
    sql = """
      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), {{interval}}) * {{interval}}) AS time,
        argMax(followers_count, dt) as followers_count
      FROM twitter_followers
      PREWHERE
        twitter_handle = {{twitter_handle}} AND
        dt >= toDateTime({{from}}) AND
        dt < toDateTime({{to}})
      GROUP BY time
      ORDER BY time
    """

    params = %{
      interval: Sanbase.DateTimeUtils.str_to_sec(interval),
      twitter_handle: twitter_handle,
      from: from,
      to: to
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp last_record_query(twitter_handle) do
    sql = """
      SELECT
        toUnixTimestamp(dt),
        followers_count
      FROM #{@table}
      PREWHERE twitter_handle = {{twitter_handle}} AND dt >= now() - INTERVAL 14 DAY
      ORDER BY dt DESC
      LIMIT 1
    """

    params = %{twitter_handle: twitter_handle}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp first_datetime_query(twitter_handle) do
    sql = """
    SELECT toUnixTimestamp(min(dt))
    FROM #{@table}
    PREWHERE
      twitter_handle = {{twitter_handle}}
    """

    params = %{twitter_handle: twitter_handle}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp last_datetime_query(twitter_handle) do
    sql = """
    SELECT toUnixTimestamp(max(dt))
    FROM #{@table}
    PREWHERE
      twitter_handle = {{twitter_handle}}
    """

    params = %{twitter_handle: twitter_handle}

    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
