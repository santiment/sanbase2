defmodule Sanbase.Clickhouse.ApiCallData do
  @table "api_call_data"
  @moduledoc ~s"""
  Get data about the API Calls that were made by users
  """

  require Sanbase.ClickhouseRepo, as: ClickhouseRepo

  @doc ~s"""
  Get a timeseries with the total number of api calls made by a user in a given interval
  """
  @spec api_call_history(non_neg_integer(), DateTime.t(), DateTime.t(), String.t()) ::
          {:ok, list(%{datetime: DateTime.t(), api_calls_count: non_neg_integer()})}
          | {:error, String.t()}
  def api_call_history(user_id, from, to, interval) do
    {query, args} = api_call_history_query(user_id, from, to, interval)

    ClickhouseRepo.query_transform(query, args, fn [t, count] ->
      %{
        datetime: DateTime.from_unix!(t),
        api_calls_count: count
      }
    end)
  end

  def active_users_count(from, to) do
    {query, args} = active_users_count_query(from, to)

    ClickhouseRepo.query_transform(query, args, fn value -> value end)
    |> case do
      {:ok, [result]} -> result
      {:error, error} -> error
    end
  end

  def users_used_api() do
    {query, args} = users_used_api_query()

    ClickhouseRepo.query_transform(query, args, fn [value] -> value end)
    |> case do
      {:ok, result} -> result
      {:error, _error} -> []
    end
  end

  def users_used_sansheets() do
    {query, args} = users_used_sansheets_query()

    ClickhouseRepo.query_transform(query, args, fn [value] -> value end)
    |> case do
      {:ok, result} -> result
      {:error, _error} -> []
    end
  end

  def api_calls_count_per_user() do
    {query, args} = api_calls_count_per_user_query()

    ClickhouseRepo.query_reduce(query, args, %{}, fn [user_id, count], acc ->
      Map.put(acc, user_id, String.to_integer(count))
    end)
    |> case do
      {:ok, result} -> result
      {:error, _error} -> %{}
    end
  end

  defp api_call_history_query(user_id, from, to, interval) do
    interval_sec = Sanbase.DateTimeUtils.str_to_sec(interval)

    query = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), ?1) * ?1) AS t,
      toUInt32(count())
    FROM
      #{@table}
    PREWHERE
      dt >= toDateTime(?2) AND
      dt < toDateTime(?3) AND
      user_id = ?4
    GROUP BY t
    ORDER BY t
    """

    args = [
      interval_sec,
      from,
      to,
      user_id
    ]

    {query, args}
  end

  defp active_users_count_query(from, to) do
    query = """
    SELECT
      uniqExact(user_id)
    FROM
      #{@table}
    PREWHERE
      dt >= toDateTime(?1) AND
      dt < toDateTime(?2)
    """

    args = [
      from,
      to
    ]

    {query, args}
  end

  defp users_used_api_query() do
    query = """
    SELECT
      distinct(user_id)
    FROM
      #{@table}
    PREWHERE
      auth_method = 'apikey' AND
      user_id != 0
    """

    {query, []}
  end

  defp users_used_sansheets_query() do
    query = """
    SELECT
      distinct(user_id)
    FROM
      #{@table}
    PREWHERE
      user_agent LIKE '%Google-Apps-Script%' AND
      user_id != 0
    """

    {query, []}
  end

  defp api_calls_count_per_user_query() do
    query = """
    SELECT
      user_id, count(*) as count
    FROM
      #{@table}
    PREWHERE auth_method = 'apikey' AND user_id != 0
    GROUP BY user_id
    ORDER BY count desc
    """

    {query, []}
  end
end
