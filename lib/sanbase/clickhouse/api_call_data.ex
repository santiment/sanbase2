defmodule Sanbase.Clickhouse.ApiCallData do
  @table "api_call_data"
  @moduledoc ~s"""
  Get data about the API Calls that were made by users
  """

  @type auth_method :: :all | :apikey | :jwt | :basic

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
    |> maybe_unwrap_ok_value()
  end

  @spec users_used_sansheets(Keyword.t()) ::
          {:ok, number()} | {:error, String.t()}
  def users_used_sansheets(opts \\ []) do
    until = Keyword.get(opts, :until, Timex.now())
    query_struct = users_used_sansheets_query(until)

    ClickhouseRepo.query_transform(query_struct, fn [value] -> value end)
    |> maybe_unwrap_ok_value()
  end

  @spec api_calls_count_per_user(Keyword.t()) ::
          {:ok, map()} | {:error, String.t()}
  def api_calls_count_per_user(opts \\ []) do
    until = Keyword.get(opts, :until, Timex.now())
    query_struct = api_calls_count_per_user_query(until)

    ClickhouseRepo.query_reduce(query_struct, %{}, fn [user_id, count], acc ->
      Map.put(acc, user_id, count)
    end)
    |> maybe_unwrap_ok_value()
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
    PREWHERE auth_method = 'apikey' AND user_id != 0
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
    PREWHERE
      dt >= toDateTime({{from}}) AND
      dt < toDateTime({{to}}) AND
      user_id = {{user_id}}
      #{maybe_filter_auth_method(auth_method)}
    GROUP BY t
    ORDER BY t
    """

    params = %{
      interval: Sanbase.DateTimeUtils.str_to_sec(interval),
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
    PREWHERE
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

  defp maybe_filter_auth_method(:all), do: ""

  defp maybe_filter_auth_method(method) when method in [:apikey, :jwt, :basic] do
    "AND auth_method = '#{method}'"
  end

  defp api_metric_distribution_query() do
    sql = """
    SELECT query, count(*) as count
    FROM api_call_data
    PREWHERE auth_method = 'apikey' AND user_id != 0
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
    PREWHERE
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
    PREWHERE
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
    PREWHERE
      dt <= toDateTime({{datetime}}) AND
      user_agent LIKE '%Google-Apps-Script%' AND
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
    PREWHERE
    dt <= toDateTime({{datetime}}) AND
    auth_method = 'apikey' AND user_id != 0
    GROUP BY user_id
    ORDER BY count desc
    """

    params = %{datetime: until}
    Sanbase.Clickhouse.Query.new(sql, params)
  end
end
