defmodule Sanbase.Clickhouse.Query do
  @moduledoc ~s"""
  A struct that holds a Clickhouse SQL query, parameters and some other options

  This struct can be used to build the string representation of an SQL query by
  using named parameters and a template. It also provides options for adding
  the Clickhous specific SETTINGS and FORMAT fragments to the query.
  """
  alias Sanbase.Clickhouse.Query.Environment

  defstruct [:sql, :parameters, :settings, :format, :environment]

  @type sql :: String.t()
  @type parameters :: Map.t()

  @type t :: %__MODULE__{
          sql: sql(),
          parameters: parameters(),
          settings: String.t() | nil,
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
    ...    settings: 'log_comment=[\'comment\']',
    ...    format: "JSONCompact"
    ...  )

    %Sanbase.Clickhouse.Query{
      sql: "SELECT * FROM intraday_metrics WHERE asset_id = get_asset_id({{slug}})) LIMIT 5",
      parameters: %{slug: "bitcoin"},
      settings: 'log_comment=[\'comment\']',
      format: "JSONCompact"
    }
  """
  @spec new(sql, parameters, Keyword.t()) :: t()
  def new(sql, parameters, opts \\ []) do
    %__MODULE__{
      sql: sql,
      parameters: parameters,
      settings: Keyword.get(opts, :settings, nil),
      format: Keyword.get(opts, :format, @default_format),
      environment: Keyword.get(opts, :environment, Environment.empty())
    }
  end

  @spec put_sql(t(), sql) :: t()
  def put_sql(struct, sql) when is_binary(sql) do
    %{struct | sql: sql}
  end

  def get_sql_text(%__MODULE__{} = query), do: query.sql
  def get_sql_parameters(%__MODULE__{} = query), do: query.parameters

  @spec put_sql(t(), parameters) :: t()
  def put_parameters(struct, parameters) when is_map(parameters) do
    %{struct | parameters: parameters}
  end

  @spec add_parameter(t(), any(), any()) :: t()
  def add_parameter(struct, key, value) do
    parameters = Map.put(struct.parameters, key, value)

    %{struct | parameters: parameters}
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

  # Private functions

  defp preprocess_query(query) do
    query
    |> trim_trailing_semicolon()
    |> add_format()
    |> add_settings()
  end

  defp trim_trailing_semicolon(%{sql: sql} = query) do
    sql = sql |> String.trim() |> String.trim_trailing(";")
    %{query | sql: sql}
  end

  defp add_settings(%{settings: nil} = struct), do: struct

  defp add_settings(%{sql: sql, settings: settings} = query) do
    sql = sql <> "\nSETTINGS #{settings}"
    %{query | sql: sql}
  end

  defp add_format(%{sql: sql, format: format} = query) do
    sql = sql <> "\nFORMAT #{format}"
    %{query | sql: sql}
  end
end
