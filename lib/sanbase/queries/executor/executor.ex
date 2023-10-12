defmodule Sanbase.Queries.Executor do
  defmodule Validator do
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
        false -> {:error, "sql query must be a non-empty binary string"}
      end
    end

    def valid_sql_parameters?(sql) do
      case Map.has_key?(sql, :parameters) and is_map(sql[:parameters]) do
        true -> :ok
        false -> {:error, "sql parameters must be a map"}
      end
    end
  end

  alias Sanbase.Queries.Query
  alias Sanbase.Queries.QueryMetadata
  alias Sanbase.Queries.Executor.Result
  alias Sanbase.Clickhouse.Query.Environment

  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  @spec run(Query.t(), QueryMetadata.t(), Environment.t()) ::
          {:ok, Result.t()} | {:error, String.t()}
  def run(%Query{} = query, %{} = query_metadata, %{} = environment) do
    query_start_time = DateTime.utc_now()

    _ = put_read_only_repo()

    %Sanbase.Clickhouse.Query{} =
      clickhouse_query = create_clickhouse_query(query, query_metadata, environment)

    case Sanbase.ClickhouseRepo.query_transform_with_metadata(
           clickhouse_query,
           &transform_result/1
         ) do
      {:ok, map} ->
        {:ok,
         %Result{
           # The query_id can be nil in case the query is ephemeral
           query_id: query.id,
           clickhouse_query_id: map.query_id,
           summary: make_summary_values_numbers(map.summary),
           rows: map.rows,
           compressed_rows: nil,
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

  defp make_summary_values_numbers(summary) do
    Map.new(summary, fn {k, v} -> {k, Sanbase.Math.to_float(v)} end)
  end

  defp put_read_only_repo() do
    # Use the pool defined by the ReadOnly repo. This is used only here
    # as this is the only place where we need to execute queries written
    # by the user. The ReadOnly repo is connecting to the database with
    # a different user that has read-only access. This is valid within
    # this process only.
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)
  end

  defp create_clickhouse_query(query, query_metadata, environment) do
    query_metadata = QueryMetadata.sanitize(query_metadata)

    opts = [settings: "log_comment='#{Jason.encode!(query_metadata)}'", environment: environment]

    Sanbase.Clickhouse.Query.new(query.sql_query_text, query.sql_query_parameters, opts)
    |> extend_sql_query(query_metadata)
  end

  defp extend_sql_query(clickhouse_query, query_metadata) do
    extended_sql =
      clickhouse_query
      |> Sanbase.Clickhouse.Query.get_sql_text()
      |> extend_query_with_prod_marker()
      |> extend_query_with_user_id_comment(query_metadata.sanbase_user_id)

    Sanbase.Clickhouse.Query.put_sql(clickhouse_query, extended_sql)
  end

  @is_prod Application.compile_env(:sanbase, :env) == :prod
  def is_prod(), do: @is_prod

  defp extend_query_with_prod_marker(query) do
    case @is_prod do
      true -> "-- __query_ran_from_prod_marker__ \n" <> query
      false -> query
    end
  end

  defp extend_query_with_user_id_comment(query, user_id) do
    "-- __sanbase_user_id_running_the_query__ #{user_id}\n" <> query
  end

  # This is passed as the transform function to the ClickhouseRepo function
  # It is executed for every row in the result set
  defp transform_result(list), do: Enum.map(list, &transform_result_value/1)

  defp transform_result_value(%Date{} = date), do: DateTime.new!(date, ~T[00:00:00])
  defp transform_result_value(%NaiveDateTime{} = ndt), do: DateTime.from_naive!(ndt, "Etc/UTC")
  defp transform_result_value(data), do: data
end
