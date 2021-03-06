defmodule Sanbase.Clickhouse.ApiCallData do
  @table "api_call_data"
  @moduledoc ~s"""
  Get data about the API Calls that were made by users
  """

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

  alias Sanbase.ClickhouseRepo

  @doc ~s"""
  Get a timeseries with the total number of api calls made by a user in a given interval
  and auth method
  """
  @spec api_call_history(non_neg_integer(), DateTime.t(), DateTime.t(), String.t(), Atom.t()) ::
          {:ok, list(%{datetime: DateTime.t(), api_calls_count: non_neg_integer()})}
          | {:error, String.t()}
  def api_call_history(user_id, from, to, interval, auth_method) do
    {query, args} = api_call_history_query(user_id, from, to, interval, auth_method)

    ClickhouseRepo.query_transform(query, args, fn [t, count] ->
      %{
        datetime: DateTime.from_unix!(t),
        api_calls_count: count
      }
    end)
  end

  @doc ~s"""
  Get a timeseries with the total number of api calls made by a user in a given interval
  and auth method
  """
  @spec api_call_count(non_neg_integer(), DateTime.t(), DateTime.t(), Atom.t()) ::
          {:ok, number()} | {:error, String.t()}
  def api_call_count(user_id, from, to, auth_method \\ :all) do
    {query, args} = api_call_count_query(user_id, from, to, auth_method)

    ClickhouseRepo.query_transform(query, args, fn [count] -> count end)
    |> maybe_unwrap_ok_value()
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
      Map.put(acc, user_id, count)
    end)
    |> case do
      {:ok, result} -> result
      {:error, _error} -> %{}
    end
  end

  def api_metric_distribution() do
    query = """
    SELECT query, count(*) as count
    FROM api_call_data
    PREWHERE auth_method = 'apikey' AND user_id != 0
    GROUP BY query
    ORDER BY count desc
    """

    ClickhouseRepo.query_transform(query, [], fn [metric, count] ->
      %{metric: metric, count: count}
    end)
    |> case do
      {:ok, result} -> result
      {:error, _error} -> []
    end
  end

  def api_metric_distribution_per_user() do
    query = """
    SELECT user_id, query, count(*) as count
    FROM api_call_data
    PREWHERE auth_method = 'apikey' AND user_id != 0
    GROUP BY user_id, query
    ORDER BY count desc
    """

    ClickhouseRepo.query_reduce(query, [], %{}, fn [user_id, metric, count], acc ->
      Map.update(acc, user_id, %{}, fn previous ->
        count_all = (previous[:count] || 0) + count

        current =
          Map.update(previous, :metrics, [], fn metrics ->
            [%{metric: metric, count: count} | metrics]
          end)

        Map.put(current, :count, count_all)
      end)
    end)
    |> case do
      {:ok, result} ->
        result
        |> Enum.sort_by(fn {_, map} -> map[:count] || 0 end, :desc)
        |> Enum.map(fn {user_id, map} -> Map.put(map, :user_id, user_id) end)

      {:error, _error} ->
        []
    end
  end

  defp api_call_history_query(user_id, from, to, interval, auth_method) do
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
      #{maybe_filter_auth_method(auth_method)}
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

  defp api_call_count_query(user_id, from, to, auth_method) do
    query = """
    SELECT
      toUInt32(count())
    FROM
      #{@table}
    PREWHERE
      dt >= toDateTime(?1) AND
      dt < toDateTime(?2) AND
      user_id = ?3
      #{maybe_filter_auth_method(auth_method)}
    """

    args = [
      from,
      to,
      user_id
    ]

    {query, args}
  end

  defp maybe_filter_auth_method(:all), do: ""

  defp maybe_filter_auth_method(method) when method in [:apikey, :jwt, :basic] do
    "AND auth_method = '#{method}'"
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
