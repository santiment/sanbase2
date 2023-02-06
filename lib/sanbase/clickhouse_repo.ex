defmodule Sanbase.ClickhouseRepo do
  # Clickhouse tests are done only through mocking the results.
  require Application

  env = Application.compile_env(:sanbase, :env)
  @adapter if env == :test, do: Ecto.Adapters.Postgres, else: ClickhouseEcto

  use Ecto.Repo, otp_app: :sanbase, adapter: @adapter

  alias Sanbase.Utils.Config

  require Logger

  # The Application supervisor checks if ths Repo is enabled. It is included in
  # the supervision tree only if this returns true
  def enabled?() do
    case Config.module_get(__MODULE__, :clickhouse_repo_enabled?) do
      true ->
        true

      false ->
        false

      nil ->
        env_var = System.get_env("CLICKHOUSE_REPO_ENABLED", "true")

        case Config.parse_boolean_value(env_var) do
          flag when is_boolean(flag) -> flag
          nil -> raise("Invalid env var CLICKHOUSE_REPO_ENABLED value: #{inspect(env_var)}")
        end
    end
  end

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.module_get(__MODULE__, :pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_DATABASE_URL"))

    {:ok, opts}
  end

  @doc ~s"""
  Execute the provided query with the given arguments.

  If the execution is successful, transform_fn/1 is used to transform each row
  of the result. transform_fn/1 accepts as argument a single list, containing one
  value per column.
  """
  def query_transform(query, args, transform_fn) when is_function(transform_fn, 1) do
    case execute_query_transform(query, args) do
      {:ok, result} -> {:ok, Enum.map(result.rows, transform_fn)}
      {:error, error} -> {:error, error}
    end
  rescue
    e ->
      log_and_return_error_from_exception(e, "query_transform/3", __STACKTRACE__)
  end

  @doc ~s"""
  Execute a query with the provided arguments. The result is enriched with some
  metadata.

  If the execution is successful, transform_fn/1 is used to transform each row
  of the result. transform_fn/1 accepts as argument a single list, containing one
  value per column. The resultcontains the same number of rows as the original result from the database.

  Return a map with the transformed rows alongside some metadata -
  the clickhouse query id, column names and a short summary of the used resources
  """
  def query_transform_with_metadata(query, args, transform_fn, attempts_left \\ 2) do
    case execute_query_transform(query, args, propagate_error: true) do
      {:ok, result} ->
        {:ok,
         %{
           rows: Enum.map(result.rows, transform_fn),
           column_names: result.columns,
           column_types: result.column_types,
           query_id: result.query_id,
           summary: result.summary
         }}

      {:error, error} ->
        case attempts_left > 0 and retryable_error?(error) do
          0 -> log_and_return_error(error, "query_transform/3")
          _ -> query_transform_with_metadata(query, args, transform_fn, attempts_left - 1)
        end
    end
  rescue
    e ->
      log_and_return_error_from_exception(e, "query_transform_with_metadata/3", __STACKTRACE__,
        propagate_error: true
      )
  end

  @doc ~s"""
  Execute a query with the provided arguments

  If the execution is successful, reducer/2 is used to reduce the result, starting
  with init_acc as the initial accumular. One example usage is to transform the
  result containing lists of asset and value to a map where the asset is the key
  and the value is the value.
  """
  def query_reduce(query, args, init_acc, reducer, attempts_left \\ 2) do
    ordered_params = order_params(query, args)
    sanitized_query = sanitize_query(query)

    maybe_store_executed_clickhouse_sql(sanitized_query, ordered_params)

    case __MODULE__.query(sanitized_query, ordered_params) do
      {:ok, result} ->
        {:ok, Enum.reduce(result.rows, init_acc, reducer)}

      {:error, error} ->
        case attempts_left > 0 and retryable_error?(error) do
          true -> query_reduce(query, args, init_acc, reducer, attempts_left - 1)
          false -> log_and_return_error(inspect(error), "query_reduce/4")
        end
    end
  rescue
    e ->
      log_and_return_error_from_exception(e, "query_reduce/4", __STACKTRACE__)
  end

  defp execute_query_transform(query, args, opts \\ []) do
    ordered_params = order_params(query, args)
    sanitized_query = sanitize_query(query)

    maybe_store_executed_clickhouse_sql(sanitized_query, ordered_params)

    case __MODULE__.query(sanitized_query, ordered_params) do
      {:ok, result} ->
        {:ok, result}

      {:error, error} ->
        log_and_return_error(error, "query_transform/3", opts)
    end
  end

  @masked_error_message "Cannot execute database query. If issue persists please contact Santiment Support."
  defp log_and_return_error_from_exception(
         %{} = exception,
         function_executed,
         stacktrace,
         opts \\ []
       ) do
    propagate_error = Keyword.get(opts, :propagate_error, false)

    log_id = UUID.uuid4()

    {_error_code, error_message} = extract_error_and_code_from_stacktrace(stacktrace)
    error_message = error_message || Exception.message(exception)

    Logger.warning("""
    [#{log_id}] Cannot execute ClickHouse #{function_executed}. Reason: #{error_message}

    Stacktrace:
    #{Exception.format_stacktrace()}
    """)

    {:error, "[#{log_id}] #{if propagate_error, do: error_message, else: @masked_error_message}"}
  end

  defp log_and_return_error(error, function_executed, opts \\ []) do
    propagate_error = Keyword.get(opts, :propagate_error, false)
    log_id = UUID.uuid4()

    {_error_code, error_message} = extract_error_code_and_message_from_error(error)

    Logger.warning(
      "[#{log_id}] Cannot execute ClickHouse #{function_executed}. Reason: #{error_message}"
    )

    {:error, "[#{log_id}] #{if propagate_error, do: error_message, else: @masked_error_message}"}
  end

  @doc ~s"""
  Replace positional params denoted as `?1`, `?2`, etc. with just `?` as they
  are not supported by ClickHouse. A complex regex is used as such character
  sequences can apear inside strings in which case they should not be removed.
  """
  def sanitize_query(query) do
    query
    |> IO.iodata_to_binary()
    |> String.replace(~r/(\?([0-9]+))(?=(?:[^\\"']|[\\"'][^\\"']*[\\"'])*$)/, "?")
  end

  @doc ~s"""
  Add artificial support for positional paramters. Extract all occurences of `?1`,
  `?2`, etc. in the query and reorder and duplicate the params so every param
  in the list appears in order as if every positional param is just `?`
  """
  def order_params(query, params) do
    sanitised =
      Regex.replace(~r/(([^\\]|^))["'].*?[^\\]['"]/, IO.iodata_to_binary(query), "\\g{1}")

    ordering =
      Regex.scan(~r/\?([0-9]+)/, sanitised)
      |> Enum.map(fn [_, x] -> String.to_integer(x) end)

    ordering_count = Enum.max_by(ordering, fn x -> x end, fn -> 0 end)

    if ordering_count != length(params) do
      raise "\nError: number of params received (#{length(params)}) does not match expected (#{ordering_count})"
    end

    ordered_params =
      ordering
      |> Enum.reduce([], fn ix, acc -> [Enum.at(params, ix - 1) | acc] end)
      |> Enum.reverse()

    case ordered_params do
      [] -> params
      _ -> ordered_params
    end
  end

  defp extract_error_and_code_from_stacktrace(stacktrace) do
    line_with_exception =
      Enum.find_value(stacktrace, fn
        {_, _, [<<_::binary>> = line | _], _} ->
          if String.contains?(line, "DB::Exception"), do: line

        _ ->
          nil
      end)

    case line_with_exception do
      nil ->
        {nil, nil}

      line ->
        {_error_code, _error_msg} = get_error_code_and_message(line)
    end
  end

  defp extract_error_code_and_message_from_error(%Clickhousex.Error{message: message}) do
    {_error_code, _error_msg} = get_error_code_and_message(message)
  end

  defp extract_error_code_and_message_from_error(error), do: {nil, error}

  defp get_error_code_and_message(error_str) do
    case String.split(error_str, "DB::Exception: ") do
      [error_str] ->
        {nil, error_str}

      [_ | _] = split_error ->
        error = List.last(split_error)

        [error_msg, error_code, _version_str] =
          Regex.split(~r|\([A-Z_]+\)|, error, include_captures: true, trim: true)

        {error_code, "#{error_code} #{error_msg}" |> String.trim()}
    end
  end

  # If the `__store_executed_clickhouse_sql__` flag is set to true
  # from the MetricResolver module, store the executed SQL query
  # after interpolating the paramters in it.
  defp maybe_store_executed_clickhouse_sql(query, params) do
    if Process.get(:__store_executed_clickhouse_sql__, false) do
      list = Process.get(:__executed_clickhouse_sql_list__, [])

      # Interpolate the paramters inside the query so it is easy to copy-paste
      interpolated_query =
        Clickhousex.Codec.Values.encode(
          %Clickhousex.Query{param_count: length(params)},
          query,
          params
        )
        |> to_string()

      Process.put(:__executed_clickhouse_sql_list__, [interpolated_query | list])

      :ok
    end
  rescue
    _ -> :ok
  end

  defp retryable_error?(error) do
    case circuit_breaker_broken?() do
      true ->
        false

      false ->
        {error_code, _error_message} =
          cond do
            error =~ "Transport Error: :timeout" -> true
            true -> false
          end
    end
  end

  defp circuit_breaker_broken?() do
    # if too many errors happened in the last X seconds, do not attempt retries
    # as the error is not here.
    false
  end
end
