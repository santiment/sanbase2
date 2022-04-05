defmodule SanbaseWeb.Graphql.Resolvers.EntityResolver do
  def get_most_voted(_root, args, _resolution) do
    types = Map.get(args, :types) || [Map.get(args, :type)]

    opts = [
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 10),
      cursor: Map.get(args, :cursor)
    ]

    execute_for_types(types, &Sanbase.Entity.get_most_voted(&1, opts))
  end

  def get_most_recent(_root, args, _resolution) do
    types = Map.get(args, :types) || [Map.get(args, :type)]

    opts = [
      page: Map.get(args, :page, 1),
      page_size: Map.get(args, :page_size, 10),
      cursor: Map.get(args, :cursor)
    ]

    execute_for_types(types, &Sanbase.Entity.get_most_recent(&1, opts))
  end

  defp execute_for_types(types, function) do
    Enum.reduce_while(types, {:ok, []}, fn type, {:ok, acc} ->
      case function.(type) do
        {:ok, result} -> {:cont, {:ok, result ++ acc}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end)
  end
end
