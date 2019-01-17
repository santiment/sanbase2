defmodule Sanbase.Timescaledb do
  @moduledoc ~s"""
  Module that contains helper functions to easily work with Timescaledb.
  It provides some common abstractions that are missing in Timescaledb, most
  notably bucketing by time and filling the gaps with zeroes.
  """

  @type argument :: any()
  @type query :: iolist() | String.t()
  @type interval :: String.t() | nil

  @doc ~s"""
  Temporary helper function that rewrites the query so it fills empty time buckets with 0.
  Will be rewritten once TimescaleDB introduces a way to fill the gaps with a first-class functions.

  PREREQUISITES for `query` and `args`:
    1. It MUST start with `SELECT`
    2. The query MUST NOT try to bucket by time and fill
    2. The first and second argument MUST be `from` and `to`
    3. The interval MUST be a string that the `transform_interval/1` function understands

    Example usage:
      You want to calculate the sum of all transaction volumes in a given time period,
      bucketed by an interval. Then your code should look like this:

          args = [from, to, contract]

          query =
           "SELECT sum(transaction_volume) AS value
            FROM eth_transaction_volume
            WHERE timestamp >= $1 AND timestamp <= $2 AND contract_address = $3"

          {query, args} = bucket_by_interval(query, args, interval)
  """
  @spec bucket_by_interval(query, list(argument), interval) :: {query, list(argument)}
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
  @spec transform_interval(interval) :: %Postgrex.Interval{}
  def transform_interval(interval) when is_binary(interval) do
    seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(interval)
    %Postgrex.Interval{secs: seconds}
  end

  @spec time_range(DateTime.t(), DateTime.t(), any()) :: String.t()
  def time_range(%DateTime{} = from, %DateTime{} = to, datetime_column_name \\ "timestamp") do
    from_unix = DateTime.to_unix(from)
    to_unix = DateTime.to_unix(to)
    "EXTRACT(epoch from #{datetime_column_name}) BETWEEN #{from_unix} AND #{to_unix}"
  end

  @doc ~s"""
  Executes the given query and args with the TimescaleRepo.
  Transforms the result by applying `transform_fn` to it. To easily handle the datetimes
  use the provided `timestamp_to_datetime` that takes the returned `timestamp` and converts
  it to Elixir's DateTime.

  Example:
   You are bucketing by interval and doing a single SUM aggregation over a field.
   In that case the result will contain two parameters in a list - `[datetime, transaction_volume]`.
   In that case your transform_fn could look like this:
     fn [datetime, transaction_volume] ->
       %{
         datetime: timestamp_to_datetime(datetime),
         transaction_volume: transaction_volume
       }
  """
  @spec timescaledb_execute({iolist() | String.t(), list(argument)}, (any() -> any())) ::
          {:ok, list(any())} | {:error, any()}
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
      #DateTime<2018-08-07 12:55:05Z>
      iex> Sanbase.Timescaledb.timestamp_to_datetime({{2015, 1, 17}, {12, 55, 37, 00005}})
      #DateTime<2015-01-17 12:55:37Z>
  """
  @spec timestamp_to_datetime({{integer, integer, integer}, {integer, integer, integer, integer}}) ::
          DateTime.t() | no_return
  def timestamp_to_datetime({date, {h, m, s, us}}) do
    NaiveDateTime.from_erl!({date, {h, m, s}}, {us, 0})
    |> DateTime.from_naive!("Etc/UTC")
  end

  @spec first_datetime(String.t(), list(argument)) :: {:ok, nil} | {:ok, DateTime.t()}
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

  @spec table_name(String.t() | atom(), String.t() | nil) :: String.t()
  def table_name(table, schema \\ nil) do
    require Sanbase.Utils.Config
    schema = schema || Sanbase.Utils.Config.get(:blockchain_schema)

    if schema do
      "#{schema}.#{table}"
    else
      table
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
