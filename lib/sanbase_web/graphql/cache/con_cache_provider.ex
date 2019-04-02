defmodule SanbaseWeb.Graphql.ConCacheProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider

  @compile :inline_list_funcs
  @compile {:inline, get: 2, store: 3, get_or_store: 4, cache_item: 3}

  @max_cache_ttl 30 * 60
  @impl true
  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl true
  def clear_all(cache) do
    cache
    |> ConCache.ets()
    |> :ets.tab2list()
    |> Enum.each(fn {key, _} -> ConCache.delete(cache, key) end)
  end

  @impl true
  def get(cache, key) do
    case ConCache.get(cache, key) do
      {:stored, value} -> value
      nil -> nil
    end
  end

  @impl true
  def store(cache, key, value) do
    case value do
      {:error, _} ->
        :ok

      {:nocache, _} ->
        Process.put(:has_nocache_field, true)
        :ok

      value ->
        cache_item(cache, key, {:stored, value})
    end
  end

  @impl true
  def get_or_store(cache, key, func, cache_modify_middleware) do
    {result, error_if_any} =
      if (result = ConCache.get(cache, key)) != nil do
        {:stored, value} = result
        {value, nil}
      else
        ConCache.isolated(cache, key, fn ->
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

              {:nocache, {:ok, _result} = value} ->
                Process.put(:has_nocache_field, true)
                {value, nil}

              value ->
                cache_item(cache, key, {:stored, value})
                {value, nil}
            end
          end
        end)
      end

    if error_if_any != nil do
      # Logger.warn("Somethting went wrong...")
      error_if_any
    else
      result
    end
  end

  defp cache_item(cache, {_, ttl} = key, value) when is_integer(ttl) and ttl <= @max_cache_ttl do
    ConCache.put(cache, key, %ConCache.Item{value: value, ttl: :timer.seconds(ttl)})
  end

  defp cache_item(cache, key, value) do
    ConCache.put(cache, key, value)
  end
end
