defmodule Sanbase.Dashboard.Query do
  alias Sanbase.Dashboard.Query

  @spec run(String.t(), Map.t(), non_neg_integer()) ::
          {:ok, Query.Result.t()} | {:error, String.t()}
  @doc ~s"""
  Compute the SQL defined in the panel by executing it against ClickHouse.

  The SQL query and arguments are taken from the panel and are executed.
  The result is transformed by converting the Date and NaiveDateTime types to DateTime.
  """
  def run(query, parameters, querying_user_id) do
    query_start_time = DateTime.utc_now()

    # Use the pool defined by the ReadOnly repo. This is used only here
    # as this is the only place where we need to execute queries written
    # by the user. The ReadOnly repo is connecting to the database with
    # a different user that has read-only access. This is valid within
    # this process only.
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    query = preprocess_query(query, querying_user_id)

    {query, args} = transform_parameters_to_args(query, parameters)

    case Sanbase.ClickhouseRepo.query_transform_with_metadata(
           query,
           args,
           &transform_result/1
         ) do
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

  def valid_sql?(sql) do
    with :ok <- valid_sql_query?(sql),
         :ok <- valid_sql_parameters?(sql) do
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

  defp transform_parameters_to_args(query, parameters) do
    parameters = take_used_parameters_subset(query, parameters)

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

  defp preprocess_query(query, user_id) do
    query
    |> extend_query_with_prod_marker()
    |> extend_query_with_user_id_comment(user_id)
    |> remove_trailing_semicolon()
  end

  defp extend_query_with_prod_marker(query) do
    case Application.get_env(:sanbase, :env) do
      :prod ->
        "-- __query_ran_from_prod_marker__ \n" <> query

      _ ->
        query
    end
  end

  defp extend_query_with_user_id_comment(query, user_id) do
    "-- __sanbase_user_id_running_the_query__ #{user_id}\n" <> query
  end

  defp remove_trailing_semicolon(query) do
    # When the query goes to the clickhouse driver, it gets extended with
    # `FORMAT JSONCompact`. If the query has a trailing `;`, this results
    # in a malformed query
    query
    |> String.trim_trailing()
    |> String.trim_trailing(";")
  end

  # Take only those parameters which are seen in the query.
  # This is useful as the SQL Editor allows you to run a subsection
  # of the query by highlighting it. Instead of doing the filtration of
  # the parameters used in this section, this check is done on the backend
  # The paramters are transformed into positional parameters, so a mismatch
  # between the number of used an provided parameters resuls in an error
  defp take_used_parameters_subset(query, parameters) do
    Enum.filter(parameters, fn {key, _value} ->
      String.contains?(query, "{{#{key}}}")
    end)
    |> Map.new()
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
