defmodule SanbaseWeb.Graphql.Middlewares.MemoryQueryCache do
  @behaviour Absinthe.Middleware
  @behaviour Absinthe.Plugin

  alias Absinthe.Resolution
  alias Absinthe.Blueprint.Document.Field

  def call(resolution, config) do
    query =
      generate_query(resolution.definition)
      |> Poison.encode!()

    cache_key =
      :crypto.hash(:sha256, query)
      |> Base.encode16()

    case ConCache.get(:graphql_cache, cache_key) do
      nil ->
        resolution

      # TODO: store the value of the resolution

      value ->
        Resolution.put_result(resolution, value)
    end
  end

  @spec generate_query(Field.t()) :: Map.t()
  defp generate_query(%Field{
         name: name,
         arguments: args,
         selections: selections
       }) do
    %{name: name}
    |> add_args(args)
    |> add_children(selections)
  end

  defp generate_query(_), do: %{}

  @spec add_args(Map.t(), List.t()) :: Map.t()
  defp add_args(result, []), do: result

  defp add_args(result, args) do
    args =
      args
      |> Enum.map(fn %Absinthe.Blueprint.Input.Argument{
                       name: name,
                       input_value: %Absinthe.Blueprint.Input.Value{data: value}
                     } ->
        {name, value}
      end)
      |> Map.new()

    Map.put(result, :args, args)
  end

  @spec add_children(Map.t(), List.t()) :: Map.t()
  defp add_children(result, []), do: result

  defp add_children(result, selections) do
    children =
      selections
      |> Enum.map(&generate_query/1)

    Map.put(result, :children, children)
  end
end
