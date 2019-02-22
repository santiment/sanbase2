defmodule SanbaseWeb.Graphql.Middlewares.BigCache do
  @behaviour Absinthe.Middleware

  alias Absinthe.Resolution
  alias SanbaseWeb.Graphql.Cache

  # def call(%{context: %{big}})

  def call(%{context: %{query_cache_key: cache_key}} = resolution, _) do
    IO.inspect(resolution.value, limit: :infinity)
    ConCache.put(Cache.cache_name(), cache_key, {:ok, resolution.value})
    resolution
  end

  def call(resolution, _), do: resolution
end
