defmodule Sanbase.MCP.Dev.SQL do
  @moduledoc """
  Runs SQL for the dev MCP tools through `Sanbase.Queries`, as the calling team member
  but with the table access of a SanAPI BUSINESS_MAX subscription, whatever the member's
  own subscriptions are.
  """

  alias Sanbase.Accounts.User
  alias Sanbase.Queries
  alias Sanbase.Queries.Executor.Result
  alias Sanbase.Queries.QueryMetadata

  @product_code "SANAPI"
  @plan_name "BUSINESS_MAX"

  @doc "The ClickHouse repo the dev MCP queries run with."
  @spec dynamic_repo() :: module()
  def dynamic_repo(), do: Queries.user_plan_to_dynamic_repo(@product_code, @plan_name)

  @doc """
  Run `sql` with `{{key}}` `parameters`. `opts` are passed to `Sanbase.Queries.run_query/4`.
  """
  @spec run(String.t(), map(), User.t(), Keyword.t()) :: {:ok, Result.t()} | {:error, String.t()}
  def run(sql, parameters, %User{} = user, opts \\ []) when is_binary(sql) do
    query = Queries.get_ephemeral_query_struct(sql, parameters || %{}, user)
    previous_repo = Process.get(:queries_dynamic_repo)
    # The Queries executor also switches ClickhouseRepo's own dynamic repo to the
    # BUSINESS_MAX pool. Put it back too, so later queries in this process are not run
    # with that pool.
    previous_clickhouse_repo = Sanbase.ClickhouseRepo.get_dynamic_repo()
    Process.put(:queries_dynamic_repo, dynamic_repo())

    try do
      case Queries.run_query(query, user, QueryMetadata.from_mcp_dev(user.id), opts) do
        {:ok, %Result{} = result} -> {:ok, result}
        {:error, error} -> {:error, error_message(error)}
      end
    rescue
      error -> {:error, Exception.message(error)}
    after
      if previous_repo,
        do: Process.put(:queries_dynamic_repo, previous_repo),
        else: Process.delete(:queries_dynamic_repo)

      Sanbase.ClickhouseRepo.put_dynamic_repo(previous_clickhouse_repo)
    end
  end

  @doc """
  The rows of `result` as maps keyed by column name, for the metadata tools.
  """
  @spec rows_as_maps(Result.t()) :: [map()]
  def rows_as_maps(%Result{columns: columns, rows: rows}) do
    Enum.map(rows, fn row -> columns |> Enum.zip(row) |> Map.new() end)
  end

  @doc """
  Make the rows of a result JSON-encodable, converting each value by its column type
  (`column_types` as in `Sanbase.Queries.Executor.Result`):

    * `UUID` becomes its canonical string. The driver decodes it as 16 raw bytes.
    * `IPv4`/`IPv6` become their text form. The driver decodes them as tuples.
    * `FixedString` stays text when it is printable (trailing NUL padding removed),
      otherwise becomes `"base64:..."`.
    * Tuples become lists, and map keys become strings (non-string keys are JSON-encoded).
    * Any other binary that is not valid UTF-8 becomes `"base64:..."`.

  Values of a type that cannot be parsed are converted by their shape alone.
  """
  @spec json_safe_rows([list()], [String.t()] | nil) :: [list()]
  def json_safe_rows(rows, column_types) do
    types = Enum.map(column_types || [], &parse_type/1)

    Enum.map(rows, fn row ->
      if length(types) == length(row),
        do: Enum.zip_with(row, types, &json_safe/2),
        else: Enum.map(row, &json_safe(&1, :unknown))
    end)
  end

  defp parse_type(type) when is_binary(type) do
    Ch.Types.decode(type)
  rescue
    _ -> :unknown
  end

  defp parse_type(_type), do: :unknown

  defp json_safe(nil, _type), do: nil
  defp json_safe(value, {:nullable, type}), do: json_safe(value, type)
  defp json_safe(value, {:low_cardinality, type}), do: json_safe(value, type)

  defp json_safe(<<_::128>> = value, :uuid) do
    {:ok, uuid} = Ecto.UUID.load(value)
    uuid
  end

  defp json_safe({_, _, _, _} = ip, :ipv4), do: ip |> :inet.ntoa() |> to_string()
  defp json_safe({_, _, _, _, _, _, _, _} = ip, :ipv6), do: ip |> :inet.ntoa() |> to_string()

  defp json_safe(value, {:fixed_string, _size}) when is_binary(value) do
    text = String.trim_trailing(value, <<0>>)
    if String.printable?(text), do: text, else: base64(value)
  end

  defp json_safe(values, {:array, type}) when is_list(values),
    do: Enum.map(values, &json_safe(&1, type))

  defp json_safe(map, {:map, key_type, value_type}) when is_map(map) and not is_struct(map) do
    Map.new(map, fn {k, v} -> {map_key(json_safe(k, key_type)), json_safe(v, value_type)} end)
  end

  defp json_safe(tuple, {:tuple, types})
       when is_tuple(tuple) and tuple_size(tuple) == length(types),
       do: tuple |> Tuple.to_list() |> Enum.zip_with(types, &json_safe/2)

  # An unknown type, or a value of an ordinary type: convert by shape.
  defp json_safe(tuple, _type) when is_tuple(tuple),
    do: tuple |> Tuple.to_list() |> Enum.map(&json_safe(&1, :unknown))

  defp json_safe(list, _type) when is_list(list), do: Enum.map(list, &json_safe(&1, :unknown))
  defp json_safe(%{__struct__: _} = struct, _type), do: struct

  defp json_safe(map, _type) when is_map(map),
    do: Map.new(map, fn {k, v} -> {map_key(json_safe(k, :unknown)), json_safe(v, :unknown)} end)

  defp json_safe(value, _type) when is_binary(value),
    do: if(String.valid?(value), do: value, else: base64(value))

  defp json_safe(value, _type), do: value

  # JSON object keys must be strings. `key` is already JSON-safe.
  defp map_key(key) when is_binary(key), do: key
  defp map_key(key), do: Jason.encode!(key)

  defp base64(value), do: "base64:" <> Base.encode64(value)

  defp error_message(error) when is_binary(error), do: error
  defp error_message(error), do: inspect(error)
end
