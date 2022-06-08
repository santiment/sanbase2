defmodule Sanbase.Dashboard.Query do
  alias Sanbase.Dashboard.Query

  @spec run(String.t(), Map.t(), String.t()) :: {:ok, Query.Result.t()} | {:error, String.t()}
  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  def run(query, parameters, san_query_id) do
    query_start_time = DateTime.utc_now()

    # Use the pool defined by the ReadOnly repo. This is used only here
    # as this is the only place where we need to execute queries written
    # by the user. The ReadOnly repo is connecting to the database with
    # a different user that has read-only access. This is valid within
    # this process only.
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    {query, args} = transform_parameters_to_args(query, parameters)

    case Sanbase.ClickhouseRepo.query_transform_with_metadata(
           query,
           args,
           &transform_result/1
         ) do
      {:ok, map} ->
        {:ok,
         %Query.Result{
           san_query_id: san_query_id,
           clickhouse_query_id: map.query_id,
           summary: map.summary,
           rows: map.rows,
           compressed_rows_json: Base.encode64(:zlib.gzip(:erlang.term_to_binary(map.rows))),
           columns: map.columns,
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

  def valid_sql?(_changeset, sql) do
    with :ok <- valid_sql_query?(sql),
         :ok <- valid_sql_args?(sql) do
      []
    else
      error -> [sql: error]
    end
  end

  def valid_sql_query?(sql) do
    case Map.has_key?(sql, :query) and is_binary(sql[:query]) do
      true -> Sanbase.Dashboard.SqlValidation.validate(sql[:query])
      false -> {:error, "sql query must be a binary string"}
    end
  end

  def valid_sql_args?(sql) do
    case Map.has_key?(sql, :parameters) and is_map(sql[:parameters]) do
      true -> :ok
      false -> {:error, "sql parameters must be a map"}
    end
  end

  defp transform_parameters_to_args(query, parameters) do
    # Transform the named parameters to positional parameters that are
    # understood by the ClickhouseRepo
    param_names = Map.keys(parameters)
    param_name_positions = Enum.with_index(param_names, 1)
    # Get the args in the same order as the param_names
    args = Enum.map(param_names, &Map.get(parameters, &1))

    query =
      Enum.reduce(param_name_positions, query, fn {param_name, position}, query_acc ->
        # Replace all occurences of {{<param_name>}} with ?<position>
        # For example: WHERE address = {{address}} => WHERE address = ?1
        kv = %{param_name => "?#{position}"}
        Sanbase.TemplateEngine.run(query_acc, kv)
      end)

    {query, args}
  end

  # This is passed as the transform function to the ClickhouseRepo function
  # It is executed for every row in the result set
  defp transform_result(list), do: Enum.map(list, &handle_result_param/1)

  defp handle_result_param(%Date{} = date),
    do: DateTime.new!(date, ~T[00:00:00])

  defp handle_result_param(%NaiveDateTime{} = ndt),
    do: DateTime.from_naive!(ndt, "Etc/UTC")

  defp handle_result_param(data), do: data
end
