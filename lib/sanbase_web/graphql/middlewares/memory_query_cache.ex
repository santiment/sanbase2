defmodule SanbaseWeb.Graphql.Middlewares.MemoryQueryCache do
  @behaviour Absinthe.Middleware
  @behaviour Absinthe.Plugin

  alias Absinthe.Resolution
  alias Absinthe.Blueprint.Document.Field
  alias Absinthe.Blueprint.Input.{Value, Argument}

  @default_ttl 60 * 1000

  def call(resolution, config) do
    ttl = Keyword.get(config, :ttl, @default_ttl)

    query =
      generate_query(resolution.definition, ttl)
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

  @spec generate_query(Field.t(), :number) :: Map.t()
  defp generate_query(
         %Field{
           name: name,
           arguments: args,
           selections: selections
         },
         ttl
       ) do
    %{name: name}
    |> add_args(args, ttl)
    |> add_children(selections, ttl)
  end

  defp generate_query(_), do: %{}

  @spec add_args(Map.t(), List.t(), :number) :: Map.t()
  defp add_args(result, [], _ttl), do: result

  defp add_args(result, args, ttl) do
    args =
      args
      |> Enum.map(fn %Argument{
                       name: name,
                       input_value: %Value{data: value}
                     } ->
        {name, convert_value(value, ttl)}
      end)
      |> Map.new()

    Map.put(result, :args, args)
  end

  @spec add_children(Map.t(), List.t(), :number) :: Map.t()
  defp add_children(result, [], _ttl), do: result

  defp add_children(result, selections, ttl) do
    children =
      selections
      |> Enum.map(&generate_query(&1, ttl))

    Map.put(result, :children, children)
  end

  # Reduce the resolution of the datetime arguments, so that they don't change
  # too often and invalidate the cache
  defp convert_value(%DateTime{} = datetime, ttl) do
    div(DateTime.to_unix(datetime, :millisecond), ttl)
  end

  defp convert_value(value, _ttl), do: value
end
