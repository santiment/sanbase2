defmodule Sanbase.Dashboard.Query do
  alias Sanbase.Dashboard.Query

  @spec run(String.t(), Map.t(), Map.t()) ::
          {:ok, Query.Result.t()} | {:error, String.t()}
  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  def run(sql, parameters, query_metadata) do
    query_start_time = DateTime.utc_now()

    # Use the pool defined by the ReadOnly repo. This is used only here
    # as this is the only place where we need to execute queries written
    # by the user. The ReadOnly repo is connecting to the database with
    # a different user that has read-only access. This is valid within
    # this process only.
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    query_metadata =
      query_metadata
      |> extend_query_metadata()
      |> escape_single_quotes()

    query =
      Sanbase.Clickhouse.Query.new(sql, parameters,
        settings: "log_comment='#{Jason.encode!(query_metadata)}'"
      )

    %{sql: sql, args: args} = Sanbase.Clickhouse.Query.get_sql_args(query)
    sql = extend_sql(sql, query_metadata)

    case Sanbase.ClickhouseRepo.query_transform_with_metadata(sql, args, &transform_result/1) do
      {:ok, map} ->
        {:ok,
         %Query.Result{
           clickhouse_query_id: map.query_id,
           summary: map.summary,
           rows: map.rows,
           compressed_rows: rows_to_compressed_rows(map.rows),
           columns: map.column_names,
           column_types: map.column_types,
           query_start_time: query_start_time,
           query_end_time: DateTime.utc_now()
         }}

      {:error, error} ->
        # This error is nice enough to be logged and returned to the user.
        # The stacktrace is parsed and relevant error messages like
        # `table X does not exist` are extracted
        {:error, error}
    end
  end

  def rows_to_compressed_rows(rows) do
    rows
    |> :erlang.term_to_binary()
    |> :zlib.gzip()
    |> Base.encode64()
  end

  def compressed_rows_to_rows(compressed_rows) do
    compressed_rows
    |> Base.decode64!()
    |> :zlib.gunzip()
    |> :erlang.binary_to_term()
  end

  def valid_sql?(args) do
    with :ok <- valid_sql_query?(args),
         :ok <- valid_sql_parameters?(args) do
      true
    end
  end

  def changeset_valid_sql?(:sql, sql) do
    case valid_sql?(sql) do
      true -> []
      {:error, error} -> [sql: error]
    end
  end

  def valid_sql_query?(sql) do
    case Map.has_key?(sql, :query) and is_binary(sql[:query]) and String.length(sql[:query]) > 0 do
      true -> :ok
      false -> {:error, "sql query must be a non-emmpty binary string"}
    end
  end

  def valid_sql_parameters?(sql) do
    case Map.has_key?(sql, :parameters) and is_map(sql[:parameters]) do
      true -> :ok
      false -> {:error, "sql parameters must be a map"}
    end
  end

  defp extend_sql(sql, query_metadata) do
    sql
    |> extend_query_with_prod_marker()
    |> extend_query_with_user_id_comment(query_metadata.sanbase_user_id)
  end

  defp extend_query_with_prod_marker(query) do
    case is_prod?() do
      true -> "-- __query_ran_from_prod_marker__ \n" <> query
      false -> query
    end
  end

  defp extend_query_metadata(%{} = query_metadata) do
    case is_prod?() do
      true -> Map.put(query_metadata, :query_ran_from_prod_marker, true)
      false -> query_metadata
    end
  end

  defp is_prod?() do
    Application.get_env(:sanbase, :env) == :prod
  end

  defp extend_query_with_user_id_comment(query, user_id) do
    "-- __sanbase_user_id_running_the_query__ #{user_id}\n" <> query
  end

  # This is passed as the transform function to the ClickhouseRepo function
  # It is executed for every row in the result set
  defp transform_result(list), do: Enum.map(list, &handle_result_param/1)

  defp handle_result_param(%Date{} = date),
    do: DateTime.new!(date, ~T[00:00:00])

  defp handle_result_param(%NaiveDateTime{} = ndt),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp handle_result_param(data), do: data

  defp escape_single_quotes(map) do
    Enum.map(map, fn {key, value} ->
      case is_binary(value) do
        true -> {key, String.replace(value, "'", "")}
        false -> {key, value}
      end
    end)
    |> Enum.into(%{})
  end
end
