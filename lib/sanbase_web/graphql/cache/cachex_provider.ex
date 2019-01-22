defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @ttl 300

  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  def clear_all(cache) do
    Cachex.clear(cache)
  end

  def get(cache, key) do
    case Cachex.get(cache, key) do
      {:ok, value} -> value
      error -> error
    end
  end

  def store(cache, key, value) do
    Cachex.put(cache, key, value)
  end

  def get_or_store(cache, key, func, cache_modify_middleware) do
    {_, result} =
      Cachex.fetch(
        cache,
        key,
        fn ->
          case func.() do
            {:middleware, _, _} = middleware ->
              {:ignore, cache_modify_middleware.(cache, key, middleware)}

            {:error, _} = error ->
              {:ignore, error}

            value ->
              {:commit, value}
          end
        end,
        ttl: @ttl
      )

    result
  end
end
