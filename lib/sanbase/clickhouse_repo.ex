defmodule Sanbase.ClickhouseRepo do
  # Clickhouse tests are done only through mocking the results.
  require Application
  @env Application.compile_env(:sanbase, :env)
  @adapter if @env == :test, do: Ecto.Adapters.Postgres, else: ClickhouseEcto

  use Ecto.Repo, otp_app: :sanbase, adapter: @adapter

  require Sanbase.Utils.Config, as: Config
  require Logger

  def enabled?() do
    System.get_env("CLICKHOUSE_REPO_ENABLED", "true") |> String.to_existing_atom()
  end

  @doc """
  Dynamically loads the repository url from the
  CLICKHOUSE_DATABASE_URL environment variable.
  """
  def init(_, opts) do
    pool_size = Config.get(:pool_size) |> Sanbase.Math.to_integer()

    opts =
      opts
      |> Keyword.put(:pool_size, pool_size)
      |> Keyword.put(:url, System.get_env("CLICKHOUSE_DATABASE_URL"))

    {:ok, opts}
  end

  @error_message "Cannot execute database query. If issue persists please contact Santiment Support."
  def query_transform(query, args, transform_fn) do
    ordered_params = order_params(query, args)
    sanitized_query = sanitize_query(query)

    __MODULE__.query(sanitized_query, ordered_params)
    |> case do
      {:ok, result} ->
        {:ok, Enum.map(result.rows, transform_fn)}

      {:error, error} ->
        log_and_return_error(inspect(error), "query_transform/3")
    end
  rescue
    e ->
      log_and_return_error(e, "query_transform/3")
  end

  def query_reduce(query, args, init, reducer) do
    ordered_params = order_params(query, args)
    sanitized_query = sanitize_query(query)

    __MODULE__.query(sanitized_query, ordered_params)
    |> case do
      {:ok, result} -> {:ok, Enum.reduce(result.rows, init, reducer)}
      {:error, error} -> log_and_return_error(inspect(error), "query_reduce/4")
    end
  rescue
    e ->
      log_and_return_error(e, "query_reduce/4")
  end

  defp log_and_return_error(%{} = e, function_executed) do
    log_id = Ecto.UUID.generate()

    Logger.warn("""
    [#{log_id}] Cannot execute ClickHouse #{function_executed}. Reason: #{Exception.message(e)}

    Stacktrace:
    #{Exception.format_stacktrace()}
    """)

    {:error, "[#{log_id}] #{@error_message}"}
  end

  defp log_and_return_error(error_str, function_executed) do
    log_id = Ecto.UUID.generate()

    Logger.warn(
      "[#{log_id}] Cannot execute ClickHouse #{function_executed}. Reason: #{error_str}"
    )

    {:error, "[#{log_id}] #{@error_message}"}
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
end
