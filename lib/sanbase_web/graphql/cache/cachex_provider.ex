defmodule SanbaseWeb.Graphql.CachexProvider do
  import Cachex.Spec

  @behaviour SanbaseWeb.Graphql.CacheProvider

  @default_ttl_seconds 300

  @compile inline: [execute_cache_miss_function: 4]

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Starts a Cachex cache with the given options.
  """
  @spec start_link(keyword()) :: {:ok, pid()} | {:error, term()}
  def start_link(opts) do
    Cachex.start_link(opts(opts))
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Returns a child spec for the Cachex cache.
  """
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(opts) do
    Supervisor.child_spec({Cachex, opts(opts)}, id: Keyword.fetch!(opts, :id))
  end

  defp opts(opts) do
    [
      name: Keyword.fetch!(opts, :name),
      # When the keys reach 2 million, remove 30% of the
      # least recently written keys
      limit: 200_000,
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
  @doc """
  Returns the size of the cache in megabytes.
  """
  @spec size(atom()) :: float()
  def size(cache) do
    {:ok, bytes_size} = Cachex.inspect(cache, {:memory, :bytes})
    (bytes_size / (1024 * 1024)) |> Float.round(2)
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Returns the number of items in the cache.
  """
  @spec count(atom()) :: integer()
  def count(cache) do
    {:ok, count} = Cachex.size(cache)
    count
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Clears all items from the cache.
  """
  @spec clear_all(atom()) :: :ok
  def clear_all(cache) do
    {:ok, _} = Cachex.clear(cache)
    :ok
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Retrieves a value from the cache by key.
  """
  @spec get(atom(), term()) :: term() | nil
  def get(cache, key) do
    case Cachex.get(cache, true_key(key)) do
      {:ok, compressed_value} when is_binary(compressed_value) ->
        decompress_value(compressed_value)

      _ ->
        nil
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Stores a value in the cache by key.
  """
  @spec store(atom(), term(), term()) :: :ok
  def store(cache, key, value) do
    case value do
      {:error, _} ->
        :ok

      {:nocache, _} ->
        Process.put(:has_nocache_field, true)

        :ok

      _ ->
        cache_item(cache, key, value)
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  @doc """
  Retrieves a value from the cache by key, or stores the result of the given function if the key is not found.
  """
  @spec get_or_store(atom(), term(), (-> term()), (atom(), term(), term() -> term())) :: term()
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)

    case Cachex.get(cache, true_key) do
      {:ok, compressed_value} when is_binary(compressed_value) ->
        decompress_value(compressed_value)

      _ ->
        execute_cache_miss_function(cache, key, func, cache_modify_middleware)
    end
  end

  @doc false
  @spec execute_cache_miss_function(atom(), term(), (-> term()), (atom(), term(), term() ->
                                                                    term())) :: term()
  defp execute_cache_miss_function(cache, key, func, cache_modify_middleware)
       when is_function(func, 0) and is_function(cache_modify_middleware, 3) do
    Cachex.fetch(
      cache,
      key,
      fn ->
        case func.() do
          {:middleware, _, _} = tuple ->
            {:ignore, cache_modify_middleware.(cache, key, tuple)}

          {:nocache, value} ->
            Process.put(:has_nocache_field, true)
            {:ignore, value}

          {:error, _} = error ->
            {:ignore, error}

          {:ok, _value} = ok_tuple ->
            cache_item(cache, key, ok_tuple)

            {:ignore, ok_tuple}
        end
      end
    )
    |> elem(1)
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
    compressed_value = compress_value(value)

    if byte_size(compressed_value) < 500_000 do
      # Do not cache items if their compressed size is > 500kb
      Cachex.put(cache, key, compressed_value, expire: :timer.seconds(ttl))
    end
  end

  defp cache_item(cache, key, value) do
    compressed_value = compress_value(value)

    if byte_size(compressed_value) < 500_000 do
      # Do not cache items if their compressed size is > 500kb
      Cachex.put(cache, key, compressed_value, expire: :timer.seconds(@default_ttl_seconds))
    end
  end

  defp true_key({key, ttl}) when is_integer(ttl), do: key
  defp true_key(key), do: key

  defp compress_value(value) do
    value
    |> :erlang.term_to_binary()
    |> :zlib.gzip()
  end

  defp decompress_value(value) do
    value
    |> :zlib.gunzip()
    |> :erlang.binary_to_term()
  end
end
