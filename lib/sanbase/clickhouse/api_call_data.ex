defmodule Sanbase.Clickhouse.ApiCallData do
  @table "api_call_data"
  @moduledoc ~s"""
  Get data about the API Calls that were made by users
  """

  @type auth_method :: :all | :apikey | :jwt | :basic

  @last_api_call_lookback_days 365

  def last_api_call_lookback_days(), do: @last_api_call_lookback_days

  import Sanbase.Utils.Transform,
    only: [maybe_unwrap_ok_value: 1, maybe_apply_function: 2, maybe_sort: 3]

  alias Sanbase.ClickhouseRepo

  @doc ~s"""
  Get a timeseries with the total number of api calls made by a user in a given interval
  and auth method
  """
  @spec api_call_history(non_neg_integer(), DateTime.t(), DateTime.t(), String.t(), auth_method) ::
          {:ok, list(%{datetime: DateTime.t(), api_calls_count: non_neg_integer()})}
          | {:error, String.t()}
  def api_call_history(user_id, from, to, interval, auth_method \\ :apikey) do
    query_struct = api_call_history_query(user_id, from, to, interval, auth_method)

    ClickhouseRepo.query_transform(query_struct, fn [t, count] ->
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
  @spec api_call_count(non_neg_integer(), DateTime.t(), DateTime.t(), auth_method) ::
          {:ok, number()} | {:error, String.t()}
  def api_call_count(user_id, from, to, auth_method \\ :apikey) do
    query_struct = api_call_count_query(user_id, from, to, auth_method)

    ClickhouseRepo.query_transform(query_struct, fn [count] -> count end)
    |> maybe_unwrap_ok_value()
  end

  @doc ~s"""
  Get the datetime of the most recent api call of a user, grouped by auth
  method. `jwt` calls come from the Sanbase webapp, `apikey` calls from
  external API usage (scripts, Sansheets, etc.)

  Looks back #{@last_api_call_lookback_days} days: the table's sorting key
  starts with `dt`, so an unbounded per-user query scans all ~7 years
  (measured 24s vs 7s with this bound). A user with no calls in the window
  is absent from the result map.
  """
  @spec last_api_call_datetime_per_auth_method(non_neg_integer()) ::
          {:ok, %{String.t() => DateTime.t()}} | {:error, String.t()}
  def last_api_call_datetime_per_auth_method(user_id) do
    query_struct = last_api_call_datetime_per_auth_method_query(user_id)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [auth_method, timestamp], acc ->
      Map.put(acc, auth_method, DateTime.from_unix!(timestamp))
    end)
  end

  @doc ~s"""
  Per-query usage of a single user since `from`: the number of calls split by
  auth method and the datetime of the last call. Metric and signal calls are
  recorded as `getMetric|<metric>` and `getSignal|<signal>`, so each metric
  gets its own row. Sorted by total calls, descending, capped at `limit` rows.
  """
  @spec user_queries_usage(non_neg_integer(), DateTime.t(), non_neg_integer()) ::
          {:ok,
           list(%{
             query: String.t(),
             apikey_calls: non_neg_integer(),
             jwt_calls: non_neg_integer(),
             other_calls: non_neg_integer(),
             total_calls: non_neg_integer(),
             last_called_at: DateTime.t()
           })}
          | {:error, String.t()}
  def user_queries_usage(user_id, from, limit \\ 1000) do
    query_struct = user_queries_usage_query(user_id, from, limit)

    ClickhouseRepo.query_transform(query_struct, fn [query, apikey, jwt, other, total, last] ->
      %{
        query: query,
        apikey_calls: apikey,
        jwt_calls: jwt,
        other_calls: other,
        total_calls: total,
        last_called_at: DateTime.from_unix!(last)
      }
    end)
  end

  @doc ~s"""
  Daily activity of a single user since `from`, one row per day and auth
  method: the number of calls and the number of distinct metrics called
  (`getMetric|<metric>` queries). Sorted by day, newest first.
  """
  @spec user_daily_usage(non_neg_integer(), DateTime.t()) ::
          {:ok,
           list(%{
             date: Date.t(),
             auth_method: String.t(),
             calls: non_neg_integer(),
             distinct_metrics: non_neg_integer()
           })}
          | {:error, String.t()}
  def user_daily_usage(user_id, from) do
    query_struct = user_daily_usage_query(user_id, from)

    ClickhouseRepo.query_transform(query_struct, fn [day, auth_method, calls, metrics] ->
      %{
        date: day |> DateTime.from_unix!() |> DateTime.to_date(),
        auth_method: auth_method,
        calls: calls,
        distinct_metrics: metrics
      }
    end)
  end

  @spec active_users_count(DateTime.t(), DateTime.t()) ::
          {:ok, number()} | {:error, String.t()}
  def active_users_count(from, to) do
    query_struct = active_users_count_query(from, to)

    ClickhouseRepo.query_transform(query_struct, fn [value] -> value end)
    |> maybe_unwrap_ok_value()
  end

  @spec users_used_api(Keyword.t()) ::
          {:ok, number()} | {:error, String.t()}
  def users_used_api(opts \\ []) do
    until = Keyword.get(opts, :until, Timex.now())
    query_struct = users_used_api_query(until)

    ClickhouseRepo.query_transform(query_struct, fn [value] -> value end)
  end

  @spec users_used_sansheets(Keyword.t()) ::
          {:ok, number()} | {:error, String.t()}
  def users_used_sansheets(opts \\ []) do
    until = Keyword.get(opts, :until, Timex.now())
    query_struct = users_used_sansheets_query(until)

    ClickhouseRepo.query_transform(query_struct, fn [value] -> value end)
  end

  @spec api_calls_count_per_user(Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def api_calls_count_per_user(opts \\ []) do
    until = Keyword.get(opts, :until, Timex.now())
    query_struct = api_calls_count_per_user_query(until)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [user_id, count], acc ->
      Map.put(acc, user_id, count)
    end)
  end

  @spec api_metric_distribution() ::
          {:ok, list(map())} | {:error, String.t()}
  def api_metric_distribution() do
    query_struct = api_metric_distribution_query()

    ClickhouseRepo.query_transform(query_struct, fn [metric, count] ->
      %{metric: metric, count: count}
    end)
    |> maybe_unwrap_ok_value()
  end

  @spec api_metric_distribution_per_user() ::
          {:ok, map()} | {:error, String.t()}
  def api_metric_distribution_per_user() do
    query_struct = api_metric_distribution_per_user_query()

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [user_id, metric, count], acc ->
      Map.update(acc, user_id, %{}, fn map ->
        update_api_distribution_user_map(map, metric, count)
      end)
    end)
    |> maybe_sort(:count, :desc)
    |> maybe_apply_function(
      &Enum.map(&1, fn {user_id, map} -> Map.put(map, :user_id, user_id) end)
    )
  end

  # Private functions

  defp update_api_distribution_user_map(map, metric, count) do
    elem = %{metric: metric, count: count}
    count_all = (map[:count] || 0) + count

    map
    |> Map.update(:metrics, [elem], &[elem | &1])
    |> Map.put(:count, count_all)
  end

  defp api_metric_distribution_per_user_query() do
    sql = """
    SELECT user_id, query, count(*) as count
    FROM api_call_data
    WHERE auth_method = 'apikey' AND user_id != 0
    GROUP BY user_id, query
    ORDER BY count desc
    """

    params = %{}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp api_call_history_query(user_id, from, to, interval, auth_method) do
    sql = """
    SELECT
      toUnixTimestamp(intDiv(toUInt32(dt), {{interval}}) * {{interval}}) AS t,
      toUInt32(count())
    FROM
      #{@table}
    WHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      user_id = {{user_id}}
      #{maybe_filter_auth_method(auth_method)}
    GROUP BY t
    ORDER BY t
    """

    params = %{
      interval: Sanbase.Utils.DateTime.str_to_sec(interval),
      from: from,
      to: to,
      user_id: user_id
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp api_call_count_query(user_id, from, to, auth_method) do
    sql = """
    SELECT
      toUInt32(count())
    FROM
      #{@table}
    WHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      user_id = {{user_id}}
      #{maybe_filter_auth_method(auth_method)}
    """

    params = %{
      from: from,
      to: to,
      user_id: user_id
    }

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp last_api_call_datetime_per_auth_method_query(user_id) do
    from = DateTime.utc_now() |> DateTime.add(-@last_api_call_lookback_days, :day)

    sql = """
    SELECT auth_method, toUnixTimestamp(max(dt))
    FROM #{@table}
    WHERE dt >= toDateTime({{from}}) AND user_id = {{user_id}}
    GROUP BY auth_method
    """

    Sanbase.Clickhouse.Query.new(sql, %{user_id: user_id, from: from})
  end

  defp user_queries_usage_query(user_id, from, limit) do
    sql = """
    SELECT
      query,
      toUInt64(countIf(auth_method = 'apikey')),
      toUInt64(countIf(auth_method = 'jwt')),
      toUInt64(countIf(auth_method NOT IN ('apikey', 'jwt'))),
      toUInt64(count()) AS total,
      toUnixTimestamp(max(dt))
    FROM #{@table}
    WHERE dt >= toDateTime({{from}}) AND user_id = {{user_id}}
    GROUP BY query
    ORDER BY total DESC
    LIMIT {{limit}}
    """

    Sanbase.Clickhouse.Query.new(sql, %{user_id: user_id, from: from, limit: limit})
  end

  # `query` is Nullable(String). Passing it to `uniqExactIf` as-is fails on
  # production ClickHouse with CANNOT_CONVERT_TYPE (Nullable vs non-Nullable
  # aggregate state), so both arguments are made non-nullable explicitly.
  defp user_daily_usage_query(user_id, from) do
    sql = """
    SELECT
      toUnixTimestamp(toStartOfDay(dt)) AS day,
      auth_method,
      toUInt64(count()),
      toUInt64(uniqExactIf(assumeNotNull(query), startsWith(ifNull(query, ''), 'getMetric|')))
    FROM #{@table}
    WHERE dt >= toDateTime({{from}}) AND user_id = {{user_id}}
    GROUP BY day, auth_method
    ORDER BY day DESC, auth_method
    """

    Sanbase.Clickhouse.Query.new(sql, %{user_id: user_id, from: from})
  end

  defp maybe_filter_auth_method(:all), do: ""

  defp maybe_filter_auth_method(method) when method in [:apikey, :jwt, :basic] do
    "AND auth_method = '#{method}'"
  end

  defp api_metric_distribution_query() do
    sql = """
    SELECT query, count(*) as count
    FROM api_call_data
    WHERE auth_method = 'apikey' AND user_id != 0
    GROUP BY query
    ORDER BY count desc
    """

    params = %{}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp active_users_count_query(from, to) do
    sql = """
    SELECT
      uniqExact(user_id)
    FROM
      #{@table}
    WHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}})
    """

    params = %{from: from, to: to}

    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp users_used_api_query(until) do
    sql = """
    SELECT
      distinct(user_id)
    FROM
      #{@table}
    WHERE
      dt <= toDateTime({{datetime}}) AND
      auth_method = 'apikey' AND
      user_id != 0
    """

    params = %{datetime: until}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp users_used_sansheets_query(until) do
    sql = """
    SELECT
      distinct(user_id)
    FROM
      #{@table}
    WHERE
      dt <= toDateTime({{datetime}}) AND
      match(user_agent, 'Sansheets/|Google-Apps-Script') AND
      user_id != 0
    """

    params = %{datetime: until}
    Sanbase.Clickhouse.Query.new(sql, params)
  end

  defp api_calls_count_per_user_query(until) do
    sql = """
    SELECT
      user_id, count(*) as count
    FROM
      #{@table}
    WHERE
    dt <= toDateTime({{datetime}}) AND
    auth_method = 'apikey' AND user_id != 0
    GROUP BY user_id
    ORDER BY count desc
    """

    params = %{datetime: until}
    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
