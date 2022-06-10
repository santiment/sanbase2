defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @default_ttl_seconds 300
  @impl SanbaseWeb.Graphql.CacheProvider

  import Cachex.Spec

  def start_link(opts) do
    Cachex.start_link(opts(opts))
  end

  def child_spec(opts) do
    Supervisor.child_spec({Cachex, opts(opts)}, id: Keyword.fetch!(opts, :id))
  end

  defp opts(opts) do
    [
      name: Keyword.fetch!(opts, :name),
      # When the keys reach 2 million, remove 30% of the
      # least recently written keys
      limit: 2_000_000,
      policy: Cachex.Policy.LRW,
      reclaim: 0.3,
      # How often the Janitor process runs to clean the cache
      interval: 5000,
      # The default TTL of keys in the cache
      expiration:
        expiration(
          default: :timer.seconds(@default_ttl_seconds),
          interval: :timer.seconds(10),
          lazy: true
        )
    ]
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def size(cache) do
    {:ok, bytes_size} = Cachex.inspect(cache, {:memory, :bytes})
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def count(cache) do
    {:ok, count} = Cachex.size(cache)
    count
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def clear_all(cache) do
    {:ok, _} = Cachex.clear(cache)
    :ok
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get(cache, key) do
    case Cachex.get(cache, true_key(key)) do
      {:ok, {:stored, value}} -> value
      _ -> nil
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

      _ ->
        cache_item(cache, key, {:stored, value})
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    {_, result} =
      Cachex.fetch(
        cache,
        true_key(key),
        fn ->
          result = func.()
          handle_fetch_function_result(cache, key, result, cache_modify_middleware)
        end,
        ttl: key_to_ttl_ms(key)
      )

    result
  end

  # This is executed from inside the Cachex.fetch/4 function. It is required to
  # return {:ignore, result} or {:commit, result} indicating whether or not the
  # result should be stored in the cache
  defp handle_fetch_function_result(cache, key, result, cache_modify_middleware) do
    case result do
      {:middleware, _, _} = tuple ->
        # Execute the same function with the new result. When the result is an
        # :ok | :error | :nocache tuple it will be handled
        middleware_result = cache_modify_middleware.(cache, key, tuple)
        handle_fetch_function_result(cache, key, middleware_result, cache_modify_middleware)

      {:nocache, value} ->
        Process.put(:has_nocache_field, true)
        {:ignore, value}

      {:error, _} = error ->
        {:ignore, error}

      value ->
        cache_item(cache, key, value)
        {:ignore, value}
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
    Cachex.put(cache, key, value, ttl: :timer.seconds(ttl))
  end

  defp cache_item(cache, key, value) do
    Cachex.put(cache, key, value, ttl: :timer.seconds(300))
  end

  defp true_key({key, ttl}) when is_integer(ttl), do: key
  defp true_key(key), do: key

  defp key_to_ttl_ms({_key, ttl}) when is_integer(ttl), do: ttl * 1000
  defp key_to_ttl_ms(_), do: @default_ttl_seconds * 1000
end
