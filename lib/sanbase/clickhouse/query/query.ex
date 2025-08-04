defmodule Sanbase.Clickhouse.Query do
  @moduledoc ~s"""
  A struct that holds a Clickhouse SQL query, parameters and some other options

  This struct can be used to build the string representation of an SQL query by
  using named parameters and a template. It also provides options for adding
  the Clickhous specific SETTINGS and FORMAT fragments to the query.
  """
  alias Sanbase.Clickhouse.Query.Environment

  defstruct [:sql, :parameters, :log_comment, :leading_comments, :format, :environment]

  @type sql :: String.t()
  @type parameters :: Map.t()

  @type t :: %__MODULE__{
          sql: sql(),
          parameters: parameters(),
          log_comment: map() | nil,
          leading_comments: [],
          environment: Environment.t(),
          format: String.t()
        }

  @default_format "JSONCompact"

  @doc ~s"""
  Create a new query by providing the SQL, positional parameters
  represented as a map and an optional list of options - settings and format.

  The SQL is parametrized by templating and named parameters.

    ## Examples
    iex> Sanbase.Clickhouse.Query.new(
    ...    "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})) LIMIT 5",
    ...    %{slug: "bitcoin"},
    ...    format: "JSONCompact"
    ...  )

    %Sanbase.Clickhouse.Query{
      sql: "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})) LIMIT 5",
      parameters: %{slug: "bitcoin"},
      format: "JSONCompact"
    }
  """
  @spec new(sql, parameters, Keyword.t()) :: t()
  def new(sql, parameters, opts \\ []) do
    %__MODULE__{
      sql: sql,
      parameters: parameters,
      log_comment: Keyword.get(opts, :log_comment, %{}),
      format: Keyword.get(opts, :format, @default_format),
      environment: Keyword.get(opts, :environment, Environment.empty()),
      leading_comments: Keyword.get(opts, :leading_comments, [])
    }
  end

  @doc ~s"""
  Add a string comment to the query. The comment will be added as a leading comment
  to the query when executed.

  For example adding "sanbase_container_type web" comment to the query `SELECT * FORM table`
  will make it so the query executed in Clickhouse will have the following format:

    -- sanbase_container_type web
    SELECT * FROM table
  """
  @spec add_leading_comment(t(), String.t()) :: t()
  def add_leading_comment(%__MODULE__{} = struct, comment) do
    %{
      struct
      | leading_comments: [comment | struct.leading_comments]
    }
  end

  @spec put_sql(t(), sql) :: t()
  def put_sql(%__MODULE__{} = struct, sql) when is_binary(sql) do
    %{struct | sql: sql}
  end

  @spec put_format(t(), String.t()) :: t()
  def put_format(struct, format) do
    %{struct | format: format}
  end

  @spec get_sql_text(t()) :: String.t()
  def get_sql_text(%__MODULE__{} = query), do: query.sql

  @spec get_sql_parameters(t()) :: map()
  def get_sql_parameters(%__MODULE__{} = query), do: query.parameters

  @spec put_sql(t(), parameters) :: t()
  def put_parameters(%__MODULE__{} = struct, parameters) when is_map(parameters) do
    %{struct | parameters: parameters}
  end

  @doc ~s"""

  """
  @spec add_parameter(t(), any(), any()) :: t()
  def add_parameter(%__MODULE__{} = struct, key, value) do
    parameters = struct.parameters |> Map.put(key, value)

    %{struct | parameters: parameters}
  end

  @doc ~s"""
  Extends the `log_comment` field of the given struct with additional data from the provided map.

  ## Parameters
  - `struct`: A `%__MODULE__{}` struct whose `log_comment` field will be extended.
  - `map`: A map containing the additional data to be merged into the `log_comment`.

  ## Returns
  The updated struct with the extended `log_comment`.

  """
  @spec extend_log_comment(t(), map()) :: t()
  def extend_log_comment(%__MODULE__{} = struct, map) when is_map(map) do
    %{
      struct
      | log_comment: Map.merge(struct.log_comment, map)
    }
  end

  @doc ~s"""
  Process the SQL query and named parameters and return a map with keys:
  - sql: The SQL query string transformed to use positional parameters, so the
    clickhousex library can use it.
  - args: The parameters transformed to a list of arguments, positionally ordered.
    Adding/removing/reordering elements in this list will cause a database error, as
    the order is specific for the sql query.
  """
  @spec get_sql_args(t()) :: {:ok, %{sql: String.t(), args: list()}} | {:error, String.t()}
  def get_sql_args(%__MODULE__{} = query) do
    query = preprocess_query(query)

    with {:ok, {sql, args}} <-
           Sanbase.TemplateEngine.run_generate_positional_params(
             query.sql,
             params: query.parameters,
             env: query.environment
           ) do
      result = %{sql: sql, args: args}
      {:ok, result}
    end
  end

  def get_sql_args_v2(%__MODULE__{} = query) do
    query = preprocess_query(query)

    with {:ok, {sql, args}} <-
           Sanbase.TemplateEngine.run_generate_positional_params_v2(
             query.sql,
             params: query.parameters,
             env: query.environment
           ) do
      result = %{sql: sql, args: args}
      {:ok, result}
    end
  end

  # Private functions

  defp preprocess_query(query) do
    query
    |> trim_trailing_semicolon()
    |> add_format()
    |> add_settings()
    |> prepend_leading_comments()
  end

  defp trim_trailing_semicolon(%{sql: sql} = query) do
    sql = sql |> String.trim() |> String.trim_trailing(";")
    %{query | sql: sql}
  end

  defp prepend_leading_comments(%{leading_comments: []} = query), do: query

  defp prepend_leading_comments(%{sql: sql, leading_comments: comments} = query) do
    comments_str =
      comments
      |> Enum.reverse()
      |> Enum.map(fn c -> "-- #{c}" end)
      |> Enum.join("\n")
      |> String.trim()
      |> String.trim_trailing("\n")

    new_sql = comments_str <> "\n" <> sql

    %{query | sql: new_sql}
  end

  defp add_settings(%{log_comment: map} = struct) when map_size(map) == 0, do: struct

  defp add_settings(%{sql: sql, log_comment: log_comment} = query) do
    settings = "log_comment='#{Jason.encode!(log_comment)}'"

    sql = sql <> "\nSETTINGS #{settings}"
    %{query | sql: sql}
  end

  defp add_format(%{format: nil} = struct), do: struct

  defp add_format(%{sql: sql, format: format} = query) when not is_nil(format) do
    sql = sql <> "\nFORMAT #{format}"
    %{query | sql: sql}
  end
end
