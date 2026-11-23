defmodule Sanbase.MCP.Dev.DescribeTablesTool do
  @moduledoc """
  Describe ClickHouse tables before querying them with `execute_sql`: for each table its
  engine, sorting, partition and primary keys, comment and columns (name, type, default,
  comment and whether the column is part of a key).

  Filter on the sorting key columns, in their order, to keep queries fast. Get table names
  from `list_tables`.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.Dev.SQL
  alias Sanbase.MCP.ToolError

  @max_tables 20

  @tables_sql """
  SELECT name, engine, sorting_key, partition_key, primary_key, total_rows, comment
  FROM system.tables
  WHERE database = 'default' AND has({{tables}}, name)
  ORDER BY name
  """

  @columns_sql """
  SELECT
    table, name, type, default_kind, default_expression, comment,
    is_in_partition_key, is_in_sorting_key, is_in_primary_key
  FROM system.columns
  WHERE database = 'default' AND has({{tables}}, table)
  ORDER BY table, position
  """

  def name(), do: "describe_tables"

  @impl true
  def annotations() do
    %{
      "title" => "Describe ClickHouse Tables",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:tables, {:list, :string},
      required: true,
      description: "Table names from `list_tables`, at most #{@max_tables}."
    )
  end

  @impl true
  def execute(%{tables: tables}, frame) do
    # A JSON null in the list passes the schema.
    {names, invalid} = Enum.split_with(tables, &is_binary/1)
    tables = names |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == "")) |> Enum.uniq()

    cond do
      invalid != [] ->
        error(frame, ToolError.permanent("`tables` must contain only table names (strings)."))

      tables == [] ->
        error(frame, ToolError.permanent("Pass at least one table name from `list_tables`."))

      length(tables) > @max_tables ->
        error(frame, ToolError.permanent("Pass at most #{@max_tables} tables per call."))

      true ->
        describe(tables, frame)
    end
  end

  defp describe(tables, frame) do
    user = frame.assigns.current_user
    params = %{"tables" => tables}
    opts = [store_execution_details: false]

    with {:ok, tables_result} <- SQL.run(@tables_sql, params, user, opts),
         {:ok, columns_result} <- SQL.run(@columns_sql, params, user, opts) do
      columns_by_table =
        columns_result
        |> SQL.rows_as_maps()
        |> Enum.group_by(& &1["table"], &column/1)

      found =
        tables_result
        |> SQL.rows_as_maps()
        |> Enum.map(&Map.put(&1, "columns", Map.get(columns_by_table, &1["name"], [])))

      found_names = MapSet.new(found, & &1["name"])

      result = %{
        tables: found,
        not_found: Enum.reject(tables, &MapSet.member?(found_names, &1))
      }

      {:reply, Response.json(Response.tool(), result), frame}
    else
      {:error, error} ->
        error(frame, ToolError.transient("Describing the tables failed: #{error}"))
    end
  end

  defp column(row) do
    %{
      "name" => row["name"],
      "type" => row["type"],
      "default_kind" => blank_to_nil(row["default_kind"]),
      "default_expression" => blank_to_nil(row["default_expression"]),
      "comment" => blank_to_nil(row["comment"]),
      "in_partition_key" => row["is_in_partition_key"] == 1,
      "in_sorting_key" => row["is_in_sorting_key"] == 1,
      "in_primary_key" => row["is_in_primary_key"] == 1
    }
  end

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  defp error(frame, message), do: {:reply, Response.error(Response.tool(), message), frame}
end
