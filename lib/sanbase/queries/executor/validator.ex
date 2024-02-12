defmodule Sanbase.Queries.Executor.Validator do
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
    case Map.has_key?(sql, :query) and is_binary(sql[:query]) and String.length(sql[:query]) > 0 do
      true -> :ok
      false -> {:error, "sql query must be a non-empty binary string"}
    end
  end

  def valid_sql_parameters?(sql) do
    case Map.has_key?(sql, :parameters) and is_map(sql[:parameters]) do
      true -> :ok
      false -> {:error, "sql parameters must be a map"}
    end
  end
end
