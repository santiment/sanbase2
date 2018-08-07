defmodule Sanbase.Timescaledb do
  @moduledoc ~s"""
  Module that contains helper functions to easily work with Timescaledb.
  It provides some common abstractions that are missing in Timescaledb, most
  notably bucketing by time and filling the gaps with zeroes.
  """

  @doc ~s"""
  Temporary helper function that rewrites the query so it fills empty time buckets with 0.
  Will be rewritten once TimescaleDB introduces a way to fill the gaps with a first-class functions.

  PREREQUISITES for `query` and `args`:
    1. It MUST start with `SELECT`
    2. The query MUST NOT try to bucket by time and fill
    2. The first and second argument MUST be `from` and `to`
    3. The interval MUST be a string that the `transform_interval/1` function understands

    Example usage:
      You want to calculate the sum of all burn rates in a given time period,
      bucketed by an interval. Then your code should look like this:

          args = [from, to, contract]

          query =
           "SELECT sum(burn_rate) AS value
            FROM eth_burn_rate
            WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3"

          {query, args} = bucket_by_interval(query, args, interval)
  """
  def bucket_by_interval(query, args, nil), do: {query, args}

  def bucket_by_interval("SELECT " <> rest_query, args, interval)
      when is_list(args) and is_binary(interval) do
    interval = transform_interval(interval)
    interval_pos = length(args) + 1

    query = [
      "WITH data AS (
      SELECT time_bucket($#{interval_pos}::interval, timestamp)::timestamp AS ts, ",
      rest_query,
      " GROUP BY ts
      ),
      period AS (
        SELECT ts::timestamp
          FROM generate_series(time_bucket($#{interval_pos}, $1), $2, $#{interval_pos}) AS ts
      )
    SELECT period.ts, coalesce(data.value, 0) as value
      FROM period
      LEFT JOIN data ON period.ts = data.ts
      ORDER BY period.ts;
    "
    ]

    {query, args ++ [interval]}
  end

  @doc ~s"""
  Transforms a string representation of an interval for usage as a postgres interval
  Examples:
   > `1h` - interval that represent 1 hours
   > `5m` - interval that represents 5 minutes
   > `3d` - interval that represents 3 days
   > `1w` - interval that represents 1 week
  """
  def transform_interval(interval) when is_binary(interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    %Postgrex.Interval{secs: seconds}
  end

  @doc ~s"""
  Executes the given query and args with the TimescaleRepo.
  Transforms the result by applying `transform_fn` to it. To easily handle the datetimes
  use the provided `timestamp_to_datetime` that takes the returned `timestamp` and converts
  it to Elixir's DateTime.

  Example:
   You are bucketing by interval and doing a single SUM aggregation over a field.
   In that case the result will contain two parameters in a list - `[datetime, burn_rate]`.
   In that case your transform_fn could look like this:
     fn [datetime, burn_rate] ->
       %{
         datetime: timestamp_to_datetime(datetime),
         burn_rate: burn_rate
       }
  """
  def timescaledb_execute({query, args}, transform_fn) when is_function(transform_fn, 1) do
    Sanbase.TimescaleRepo.query(query, args)
    |> case do
      {:ok, %{rows: rows}} ->
        result =
          Enum.map(
            rows,
            transform_fn
          )

        {:ok, result}

      {:error, error} ->
        {:error, error}
    end
  end

  @doc ~s"""
  Converts the Elixir's representation of postgres' timestamp to DateTime struct
  with UTC timezone.

   ## Examples

      iex> Sanbase.Timescaledb.timestamp_to_datetime({{2018, 8, 7}, {12, 55, 5, 00}})
      #DateTime<2018-08-07 12:55:05.00Z>
      iex> Sanbase.Timescaledb.timestamp_to_datetime({{2015, 1, 17}, {12, 55, 37, 00005}})
      #DateTime<2015-01-17 12:55:37.00Z>
  """
  def timestamp_to_datetime({date, {h, m, s, us}}) do
    NaiveDateTime.from_erl!({date, {h, m, s}}, {us, 2})
    |> DateTime.from_naive!("Etc/UTC")
  end

  def first_datetime(from_where, args) do
    query = [
      "SELECT timestamp ",
      from_where,
      "ORDER BY timestamp LIMIT 1"
    ]

    {:ok, result} =
      timescaledb_execute({query, args}, fn [timestamp] ->
        {:ok, timestamp_to_datetime(timestamp)}
      end)

    case List.first(result) do
      nil -> {:ok, nil}
      data -> data
    end
  end

  # Currently unused
  defmacro time_bucket(interval) do
    quote do
      fragment(
        "time_bucket(?::interval, timestamp)",
        unquote(interval)
      )
    end
  end

  # Currently unused
  defmacro time_bucket() do
    quote do
      fragment("time_bucket")
    end
  end

  # Currently unused
  defmacro coalesce(left, right) do
    quote do
      fragment("coalesce(?, ?)", unquote(left), unquote(right))
    end
  end

  # Currently unused
  defmacro generate_series(from, to, interval) do
    quote do
      fragment(
        """
        select generate_series(time_bucket(?::interval, ?), ?, ?::interval)::timestamp AS d
        """,
        unquote(interval),
        unquote(from),
        unquote(to),
        unquote(interval)
      )
    end
  end
end
