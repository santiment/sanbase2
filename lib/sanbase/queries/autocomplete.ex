defmodule Sanbase.Clickhouse.Autocomplete do
  @moduledoc false
  alias Sanbase.Clickhouse.Query
  alias Sanbase.ClickhouseRepo

  def get_data do
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    result = %{
      columns: get_columns(),
      functions: get_functions(),
      tables: get_tables()
    }

    {:ok, result}
  end

  defp get_tables do
    sql = """
    SELECT name, engine, partition_key, sorting_key, primary_key
    FROM system.tables
    WHERE database = 'default' AND name NOT LIKE '%_shard%'
    """

    query_struct = Query.new(sql, %{})

    {:ok, result} =
      ClickhouseRepo.query_transform(
        query_struct,
        fn [
             name,
             engine,
             partition_key,
             sorting_key,
             primary_key
           ] ->
          %{
            name: name,
            engine: engine,
            partition_key: partition_key,
            sorting_key: sorting_key,
            primary_key: primary_key
          }
        end
      )

    result
  end

  defp get_columns do
    sql = """
    SELECT table, name, type, is_in_partition_key, is_in_sorting_key, is_in_primary_key
    FROM system.columns
    WHERE database = 'default'
    """

    query_struct = Query.new(sql, %{})

    {:ok, result} =
      ClickhouseRepo.query_transform(
        query_struct,
        fn [
             table,
             name,
             type,
             is_in_partition_key,
             is_in_sorting_key,
             is_in_primary_key
           ] ->
          %{
            table: table,
            name: name,
            type: type,
            is_in_partition_key: is_in_partition_key == 1,
            is_in_sorting_key: is_in_sorting_key == 1,
            is_in_primary_key: is_in_primary_key == 1
          }
        end
      )

    result
  end

  defp get_functions do
    sql = """
    SELECT name
    FROM system.functions
    """

    query_struct = Query.new(sql, %{})
    {:ok, result} = ClickhouseRepo.query_transform(query_struct, fn [name] -> %{name: name} end)
    result
  end
end
