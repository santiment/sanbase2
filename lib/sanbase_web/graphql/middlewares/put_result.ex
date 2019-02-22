defmodule SanbaseWeb.Graphql.Middlewares.PutResult do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Cache

  def call(
        %{
          context: %{query_cache_key: cache_key} = context
        } = resolution,
        _
      ) do
    # %{schema_node: schema_node} = path |> List.first()
    # IO.inspect(schema_node)
    # IO.inspect(schema_node.middleware)

    # Process.sleep(100_000)

    case ConCache.get(Cache.cache_name(), cache_key) do
      nil ->
        resolution

      {:ok, value} ->
        # middleware =
        #   resolution.middleware
        #   |> Enum.reject(fn
        #     {{x, _}, _} ->
        #       x == Absinthe.Resolution

        #     {x, _} ->
        #       x == Absinthe.Phase.Document.Execution.Resolution

        #     _ ->
        #       false
        #   end)

        # selections =
        #   selections
        #   |> Enum.map(fn %{schema_node: schema_node} = field ->
        #     middleware =
        #       middleware
        #       |> Enum.reject(fn
        #         {{x, _}, _} ->
        #           x == Absinthe.Resolution

        #         {x, _} ->
        #           x == Absinthe.Phase.Document.Execution.Resolution

        #         _ ->
        #           false
        #       end)

        #     %{field | schema_node: %{schema_node | middleware: middleware}}
        #   end)

        # path =
        #   path
        #   |> Enum.map(fn
        #     %{schema_node: %{middleware: middleware} = schema_node} = field ->
        #       middleware =
        #         middleware
        #         |> Enum.reject(fn
        #           {{x, _}, _} ->
        #             x == Absinthe.Resolution

        #           {x, _} ->
        #             x == Absinthe.Phase.Document.Execution.Resolution

        #           _ ->
        #             false
        #         end)

        #       %{field | schema_node: %{schema_node | middleware: middleware}}

        #     field ->
        #       field
        #   end)

        IO.inspect("MARK AS RESOLVED!")

        %{
          resolution
          | state: :resolved,
            value: value,
            context: Map.put(context, :big_cache_resolved, true)
            # middleware: middleware,
            # path: path,
            # definition: %{definition | selections: selections}
        }
    end
  end

  def call(resolution, _), do: resolution
end
