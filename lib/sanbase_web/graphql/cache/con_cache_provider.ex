defmodule SanbaseWeb.Graphql.ConCacheProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider

  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  def clear_all(cache) do
    cache
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(cache, key) end)
  end

  def get(cache, key) do
    case ConCache.get(cache, key) do
      {:stored, value} -> value
      nil -> nil
    end
  end

  def store(cache, key, value) do
    ConCache.put(cache, key, {:stored, value}) == :ok
  end

  def get_or_store(cache, key, func, cache_modify_middleware) do
    {result, error_if_any} =
      if (result = ConCache.get(cache, key)) != nil do
        {:stored, value} = result
        {value, nil}
      else
        case func.() do
          {:error, _} = error ->
            {nil, error}

          {:middleware, _, _} = tuple ->
            # Decides on its behalf whether or not to put the value in the cache
            {cache_modify_middleware.(cache, key, tuple), nil}

          value ->
            ConCache.put(cache, key, {:stored, value})
            {value, nil}
        end
      end

    if error_if_any != nil do
      # Logger.warn("Somethting went wrong...")
      error_if_any
    else
      result
    end
  end
end
