defmodule Sanbase.Dashboard.Autocomplete do
  alias Sanbase.ClickhouseRepo

  def get_data(opts \\ []) do
    Sanbase.ClickhouseRepo.put_dynamic_repo(Sanbase.ClickhouseRepo.ReadOnly)

    result = %{
      columns: get_columns(),
      functions: get_functions(opts),
      tables: get_tables()
    }

    {:ok, result}
  end

  defp get_tables() do
    sql = """
    SELECT name, engine, partition_key, sorting_key, primary_key
    FROM system.tables
    WHERE database = 'default'
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

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

  defp get_columns() do
    sql = """
    SELECT table, name, type, is_in_partition_key, is_in_sorting_key, is_in_primary_key
    FROM system.columns
    WHERE database = 'default'
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

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

  defp get_functions(opts) do
    filter_functions =
      case Keyword.get(opts, :functions_filter) do
        :user_defined -> "origin = 'SQLUserDefined'"
        :system -> "origin = 'System'"
        _ -> nil
      end

    sql = """
    SELECT name, origin
    FROM system.functions
    #{if filter_functions, do: "WHERE #{filter_functions}"}
    """

    query_struct = Sanbase.Clickhouse.Query.new(sql, %{})

    {:ok, result} =
      ClickhouseRepo.query_transform(query_struct, fn [name, origin] ->
        %{name: name, origin: origin}
      end)

    result
    # TODO: Remove after cleanup
    |> Enum.reject(&(&1.name =~ ~r"boris|tzanko"))
  end
end
