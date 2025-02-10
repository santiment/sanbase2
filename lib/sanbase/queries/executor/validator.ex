defmodule Sanbase.Queries.Executor.Validator do
  @moduledoc false
  def valid_sql?(args) do
    with :ok <- valid_sql_query?(args),
         :ok <- valid_sql_parameters?(args) do
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
    if Map.has_key?(sql, :query) and is_binary(sql[:query]) and String.length(sql[:query]) > 0 do
      :ok
    else
      {:error, "sql query must be a non-empty binary string"}
    end
  end

  def valid_sql_parameters?(sql) do
    if Map.has_key?(sql, :parameters) and is_map(sql[:parameters]) do
      :ok
    else
      {:error, "sql parameters must be a map"}
    end
  end
end
