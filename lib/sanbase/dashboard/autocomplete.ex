defmodule Sanbase.Dashboard.Autocomplete do
  alias Sanbase.ClickhouseRepo

  def get_data() do
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    result = %{
      columns: get_columns(),
      functions: get_functions(),
      tables: get_tables()
    }

    {:ok, result}
  end

  defp get_tables() do
    query = """
    SELECT name, engine, partition_key, sorting_key, primary_key
    FROM system.tables
    WHERE database = 'default'
    """

    {:ok, result} =
      ClickhouseRepo.query_transform(
        query,
        [],
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

  defp get_columns() do
    query = """
    SELECT table, name, type, is_in_partition_key, is_in_sorting_key, is_in_primary_key
    FROM system.columns
    WHERE database = 'default'
    """

    {:ok, result} =
      ClickhouseRepo.query_transform(
        query,
        [],
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

  defp get_functions() do
    query = """
    SELECT name
    FROM system.functions
    """

    {:ok, result} = ClickhouseRepo.query_transform(query, [], fn [name] -> %{name: name} end)
    result
  end
end
