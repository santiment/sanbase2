defmodule SanbaseWeb.Graphql.CachexCacheProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @max_cache_ttl 86_400

  @impl SanbaseWeb.Graphql.CacheProvider
  def size(cache, :megabytes) do
    bytes_size = :ets.info(ConCache.ets(cache), :memory) * :erlang.system_info(:wordsize)
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def clear_all(cache) do
    case Cachex.clear(cache) do
      {:ok, _} -> :ok
      {:error, error} -> {:error, error}
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get(cache, key) do
    case Cachex.get(cache, true_key(key)) do
      {:ok, {:stored, value}} -> value
      {:ok, nil} -> nil
      {:error, error} -> {:error, error}
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
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

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)

    case Cachex.get!(cache, true_key) do
      {:stored, value} ->
        value

      _ ->
        transactional_run_function(cache, key, true_key, func, cache_modify_middleware)
    end
  end

  # Private functions

  defp transactional_run_function(cache, key, true_key, func, cache_modify_middleware) do
    # This crashes in case the true_key is already locked. Must be done with a
    # custom spinlock with using Cachex.locked?
    {_, result} =
      Cachex.fetch(cache, true_key, fn _true_key ->
        case Cachex.get!(cache, true_key) do
          {:stored, value} ->
            {:ignore, value}

          _ ->
            case func.() do
              {:error, _} = error ->
                {:ignore, error}

              {:middleware, _, _} = tuple ->
                # Decides on its behalf whether or not to put the value in the cache
                {:ignore, cache_modify_middleware.(cache, key, tuple)}

              {:nocache, {:ok, _result} = value} ->
                Process.put(:do_not_cache_query, true)
                {:ignore, value}

              value ->
                cache_item(cache, key, {:stored, value})
                {:ignore, value}
            end
        end
      end)

    result
  end

  defp cache_item(cache, {_key, ttl} = key, value)
       when is_integer(ttl) and ttl <= @max_cache_ttl do
    Cachex.put(cache, true_key(key), value, ttl: :timer.seconds(ttl))
  end

  defp cache_item(cache, key, value) do
    Cachex.put(cache, true_key(key), value)
  end

  defp true_key({key, ttl}) when is_integer(ttl) and ttl <= @max_cache_ttl, do: key
  defp true_key(key), do: key
end
