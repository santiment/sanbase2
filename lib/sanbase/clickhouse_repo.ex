defmodule Sanbase.ClickhouseRepo do
  # Clickhouse tests are done only through mocking the results.
  require Application

  env = Application.compile_env(:sanbase, :env)
  @adapter if env == :test, do: Ecto.Adapters.Postgres, else: ClickhouseEcto

  use Ecto.Repo, otp_app: :sanbase, adapter: @adapter

  alias Sanbase.Utils.Config
  require Logger

  def enabled?() do
    case Config.module_get(__MODULE__, :clickhouse_repo_enabled?) do
      true -> true
      false -> false
      nil -> System.get_env("CLICKHOUSE_REPO_ENABLED", "true") |> String.to_existing_atom()
    end
  end

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.module_get(__MODULE__, :pool_size) |> Sanbase.Math.to_integer()
    url = System.get_env("CLICKHOUSE_DATABASE_URL")

    opts =
      opts
      |> Keyword.merge(url_to_opts(url))
      |> Keyword.put(:pool_size, pool_size)

    {:ok, opts}
  end

  def url_to_opts(""), do: []

  def url_to_opts(url) when is_binary(url) do
    info = URI.parse(url)

    destructure [username, password], info.userinfo && String.split(info.userinfo, ":")
    "/" <> database = info.path

    scheme =
      case String.starts_with?(url, "https://") do
        true -> :https
        _ -> :http
      end

    Keyword.new()
    |> Keyword.put(:hostname, info.host)
    |> Keyword.put(:port, info.port)
    |> Keyword.put(:username, username)
    |> Keyword.put(:database, database)
    |> Keyword.put(:scheme, scheme)
  end

  @doc ~s"""
  Execute a query and apply `transform_fn/1` on each row of the result.
  """
  @spec query_transform(Sanbase.Clickhouse.Query.t(), (list() -> list())) ::
          {:ok, any()} | {:error, String.t()}
  @spec query_transform(String.t(), list(), (list() -> list())) ::
          {:ok, any()} | {:error, String.t()}
  def query_transform(%Sanbase.Clickhouse.Query{} = query, transform_fn) do
    %{sql: sql, args: args} = Sanbase.Clickhouse.Query.get_sql_args(query)
    query_transform(sql, args, transform_fn)
  end

  def query_transform(query, args, transform_fn) do
    case execute_query_transform(query, args) do
      {:ok, result} -> {:ok, Enum.map(result.rows, transform_fn)}
      {:error, error} -> {:error, error}
    end
  rescue
    e ->
      log_and_return_error_from_exception(e, "query_transform/3", __STACKTRACE__)
  end

  @doc ~s"""
  Execute a query and apply the transform_fn on every row the result.
  Return a map with the transformed rows alongside some metadata -
  the query id, column names and a short summary of the used resources
  """
  @spec query_transform_with_metadata(Sanbase.Clickhouse.Query.t(), (list() -> list())) ::
          {:ok, Map.t()} | {:error, String.t()}
  @spec query_transform_with_metadata(String.t(), list(), (list() -> list())) ::
          {:ok, Map.t()} | {:error, String.t()}
  def query_transform_with_metadata(%Sanbase.Clickhouse.Query{} = query, transform_fn) do
    %{sql: sql, args: args} = Sanbase.Clickhouse.Query.get_sql_args(query)
    query_transform_with_metadata(sql, args, transform_fn)
  end

  def query_transform_with_metadata(query, args, transform_fn) do
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
        {:error, error}
    end
  rescue
    e ->
      log_and_return_error_from_exception(e, "query_transform_with_metadata/3", __STACKTRACE__,
        propagate_error: true
      )
  end

  @doc ~s"""
  Execute a query and reduce all the rows, starting with `init` as initial accumulator
  and using `reduce` for every row
  """
  @spec query_reduce(Sanbase.Clickhouse.Query.t(), acc, (list(), acc -> acc)) ::
          {:ok, Map.t()} | {:error, String.t()}
        when acc: any
  @spec query_reduce(String.t(), list(), acc, (list(), acc -> acc)) ::
          {:ok, Map.t()} | {:error, String.t()}
        when acc: any
  def query_reduce(%Sanbase.Clickhouse.Query{} = query, init, reducer) do
    %{sql: sql, args: args} = Sanbase.Clickhouse.Query.get_sql_args(query)
    query_reduce(sql, args, init, reducer)
  end

  def query_reduce(query, args, init, reducer) do
    ordered_params = order_params(query, args)
    sanitized_query = sanitize_query(query)

    maybe_store_executed_clickhouse_sql(sanitized_query, ordered_params)

    case __MODULE__.query(sanitized_query, ordered_params) do
      {:ok, result} -> {:ok, Enum.reduce(result.rows, init, reducer)}
      {:error, error} -> log_and_return_error(error, "query_reduce/4")
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
    error_message = extract_error_from_stacktrace(stacktrace) || Exception.message(exception)

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

    error_message = extract_error_from_error(error)

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

  defp extract_error_from_stacktrace(stacktrace) do
    line_with_exception =
      Enum.find_value(stacktrace, fn
        {_, _, [<<_::binary>> = line | _], _} ->
          if String.contains?(line, "DB::Exception"), do: line

        _ ->
          nil
      end)

    case line_with_exception do
      nil -> nil
      line -> transform_error_string(line)
    end
  end

  # %Clickhousex.Error{} is causing some errors
  defp extract_error_from_error(%_{message: message}) do
    transform_error_string(message)
  end

  defp extract_error_from_error(error), do: error

  defp transform_error_string(error_str) do
    case String.split(error_str, "DB::Exception: ") do
      [error_str] ->
        error_str

      [_ | _] = split_error ->
        error = List.last(split_error)

        [error_msg, error_code, _version_str] =
          Regex.split(~r|\([A-Z_]+\)|, error, include_captures: true, trim: true)

        error_msg =
          case String.split(error_msg, "SETTINGS log_comment", parts: 2) do
            [_] ->
              error_msg

            [stripped_error_msg, _] ->
              # Exclude the SETTINGS fragment from the error response
              # so it is not shown in the result. The SETTINGS fragment
              # are appended by the preprocessing done in the backend
              # and not by the user, who will see the error
              stripped_error_msg
          end

        "#{error_code} #{error_msg}" |> String.trim()
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
end
