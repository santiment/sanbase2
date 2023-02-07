defmodule Sanbase.Clickhouse.Query do
  @moduledoc ~s"""
  A struct that holds a Clickhouse SQL query, parameters and some other options

  This struct can be used to build the string representation of an SQL query by
  using named parameters and a template. It also provides options for adding
  the Clickhous specific SETTINGS and FORMAT fragments to the query.
  """
  defstruct [:sql, :parameters, :settings, :format]

  @type t :: %__MODULE__{
          sql: String.t(),
          parameters: Map.t(),
          settings: String.t() | nil,
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
  def new(sql, parameters, opts \\ []) do
    %__MODULE__{
      sql: sql,
      parameters: parameters,
      settings: Keyword.get(opts, :settings, nil),
      format: Keyword.get(opts, :format, @default_format)
    }
  end

  @doc ~s"""
  Process the SQL query and named parameters and return
  - the SQL query string transformed to use positional parameters
  - the parameters transformed to a list of arguments, positionally ordered
  """
  def get_sql_args(%__MODULE__{} = query) do
    query = preprocess_query(query)
    {sql, args} = transform_parameters_to_args(query)

    %{sql: sql, args: args}
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

  defp transform_parameters_to_args(%{sql: sql, parameters: parameters}) do
    parameters = take_used_parameters_subset(sql, parameters)

    # Transform the named parameters to positional parameters that are
    # understood by the ClickhouseRepo
    param_names = Map.keys(parameters)
    param_name_positions = Enum.with_index(param_names, 1)
    # Get the args in the same order as the param_names
    args = Enum.map(param_names, &Map.get(parameters, &1))

    sql =
      Enum.reduce(param_name_positions, sql, fn {param_name, position}, sql_acc ->
        # Replace all occurences of {{<param_name>}} with ?<position>
        # For example: WHERE address = {{address}} => WHERE address = ?1
        kv = %{param_name => "?#{position}"}
        Sanbase.TemplateEngine.run(sql_acc, kv)
      end)

    {sql, args}
  end

  # Take only those parameters which are seen in the query.
  # This is useful as the SQL Editor allows you to run a subsection
  # of the query by highlighting it. Instead of doing the filtration of
  # the parameters used in this section, this check is done on the backend
  # The paramters are transformed into positional parameters, so a mismatch
  # between the number of used an provided parameters resuls in an error
  defp take_used_parameters_subset(sql, parameters) do
    Enum.filter(parameters, fn {key, _value} ->
      String.contains?(sql, "{{#{key}}}")
    end)
    |> Map.new()
  end
end
