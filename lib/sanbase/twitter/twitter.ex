defmodule Sanbase.Twitter do
  @table "twitter_followers"

  def timeseries_data(twitter_handle, from, to, interval) do
    {query, args} = timeseries_data_query(twitter_handle, from, to, interval)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [dt, value] ->
      %{
        datetime: DateTime.from_unix!(dt),
        value: value
      }
    end)
  end

  def last_record(twitter_handle) do
    {query, args} = last_record_query(twitter_handle)

    Sanbase.ClickhouseRepo.query_transform(query, args, fn [dt, value] ->
      %{
        datetime: dt,
        followers_count: value
      }
    end)
  end

  def first_datetime(twitter_handle) do
    {query, args} = first_datetime_query(twitter_handle)
    Sanbase.ClickhouseRepo.query_transform(query, args, fn [dt] -> dt end)
  end

  def last_datetime(twitter_handle) do
    {query, args} = last_datetime_query(twitter_handle)
    Sanbase.ClickhouseRepo.query_transform(query, args, fn [dt] -> dt end)
  end

  # private

  defp timeseries_data_query(twitter_handle, from, to, interval) do
    interval = Sanbase.DateTimeUtils.str_to_sec(interval)

    query = """
      SELECT
        toUnixTimestamp(intDiv(toUInt32(toDateTime(dt)), ?1) * ?1) AS time,
        argMax(followers_count, dt) as followers_count
      FROM twitter_followers
      PREWHERE
        twitter_handle = ?2 AND
        dt >= toDateTime(?3) AND
        dt < toDateTime(?4)
      GROUP BY time
      ORDER BY time
    """

    args = [interval, twitter_handle, from, to]

    {query, args}
  end

  defp last_record_query(twitter_handle) do
    query = """
      SELECT
        dt,
        followers_count
      FROM #{@table}
      PREWHERE twitter_handle = ?1 AND dt >= now() - INTERVAL 14 DAY
      ORDER BY dt DESC
      LIMIT 1
    """

    {query, [twitter_handle]}
  end

  defp first_datetime_query(twitter_handle) do
    query = """
    SELECT min(dt)
    FROM #{@table}
    PREWHERE
      twitter_handle = ?1
    """

    args = [twitter_handle]
    {query, args}
  end

  defp last_datetime_query(twitter_handle) do
    query = """
    SELECT max(dt)
    FROM #{@table}
    PREWHERE
      twitter_handle = ?1
    """

    args = [twitter_handle]
    {query, args}
  end
end
