defmodule Sanbase.MCP.Dev.ListTablesTool do
  @moduledoc """
  List the ClickHouse tables `execute_sql` can read: name, engine, sorting and partition
  keys, row count and comment.

  Pass `name_filter` to keep only tables whose name contains it (case-insensitive). Then
  call `describe_tables` for the columns of the tables you will query.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.Dev.SQL
  alias Sanbase.MCP.ToolError

  @sql """
  SELECT name, engine, sorting_key, partition_key, total_rows, comment
  FROM system.tables
  WHERE database = 'default'
    AND NOT is_temporary
    AND name NOT LIKE '%_shard%'
    AND NOT startsWith(name, '.inner')
    AND positionCaseInsensitive(name, {{name_filter}}) > 0
  ORDER BY name
  """

  def name(), do: "list_tables"

  @impl true
  def annotations() do
    %{
      "title" => "List ClickHouse Tables",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:name_filter, :string,
      description: "Keep only tables whose name contains this text (case-insensitive)."
    )
  end

  @impl true
  def execute(params, frame) do
    name_filter = params |> Map.get(:name_filter) |> to_string() |> String.trim()
    user = frame.assigns.current_user

    case SQL.run(@sql, %{"name_filter" => name_filter}, user, store_execution_details: false) do
      {:ok, result} ->
        tables = SQL.rows_as_maps(result)

        {:reply, Response.json(Response.tool(), %{count: length(tables), tables: tables}), frame}

      {:error, error} ->
        message = ToolError.transient("Listing the tables failed: #{error}")
        {:reply, Response.error(Response.tool(), message), frame}
    end
  end
end
