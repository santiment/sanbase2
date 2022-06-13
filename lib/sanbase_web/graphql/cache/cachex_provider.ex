defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @default_ttl_seconds 300

  import Cachex.Spec

  @compile inline: [
             execute_cache_miss_function: 5,
             handle_execute_cache_miss_function: 4,
             obtain_lock: 3
           ]

  @impl SanbaseWeb.Graphql.CacheProvider
  def start_link(opts) do
    Cachex.start_link(opts(opts))
  end

  @impl SanbaseWeb.Graphql.CacheProvider
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
    true_key = true_key(key)

    case Cachex.get(cache, true_key) do
      {:ok, {:stored, value}} ->
        value

      _ ->
        cache_record = Cachex.Services.Overseer.ensure(cache)

        execute_cache_miss_function(cache, cache_record, key, func, cache_modify_middleware)
    end
  end

  defp execute_cache_miss_function(cache, cache_record, key, func, cache_modify_middleware) do
    # This is the only place where we need to have the transactional get_or_store
    # mechanism. Cachex.fetch! is running in multiple processes, which causes issues
    # when testing. Cachex.transaction has a non-configurable timeout. We actually
    # can achieve the required behavior by manually getting and realeasing the lock.
    # The transactional guarantees are not needed.

    try do
      true = obtain_lock(cache_record, [true_key(key)])

      case Cachex.get(cache, true_key(key)) do
        {:ok, {:stored, value}} ->
          # First check if the result has not been stored while waiting for the lock.
          value

        _ ->
          handle_execute_cache_miss_function(
            cache,
            key,
            _result = func.(),
            cache_modify_middleware
          )
      end
    after
      true = Cachex.Services.Locksmith.unlock(cache_record, [true_key(key)])
    end
  end

  defp obtain_lock(cache_record, keys, attempt \\ 0)

  defp obtain_lock(_cache_record, _keys, 30) do
    raise("Obtaining cache lock failed because of timeout")
  end

  defp obtain_lock(cache_record, keys, attempt) do
    case Cachex.Services.Locksmith.lock(cache_record, keys) do
      false ->
        # In case the lock cannot be obtained, try again after some time
        # In the beginning the next attempt is scheduled in an exponential
        # backoff fashion - 10, 130, 375, 709, etc. milliseconds
        # The backoff is capped at 2 seconds
        sleep_ms = (:math.pow(attempt * 20, 1.6) + 10) |> trunc()
        sleep_ms = Enum.max([sleep_ms, 2000])

        Process.sleep(sleep_ms)
        obtain_lock(cache_record, keys, attempt + 1)

      true ->
        true
    end
  end

  defp handle_execute_cache_miss_function(cache, key, result, cache_modify_middleware) do
    case result do
      {:middleware, _, _} = tuple ->
        cache_modify_middleware.(cache, key, tuple)

      {:nocache, value} ->
        Process.put(:has_nocache_field, true)
        value

      {:error, _} = error ->
        error

      {:ok, _value} = ok_tuple ->
        cache_item(cache, key, {:stored, ok_tuple})
        ok_tuple
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
    Cachex.put(cache, key, value, ttl: :timer.seconds(ttl))
  end

  defp cache_item(cache, key, value) do
    Cachex.put(cache, key, value, ttl: :timer.seconds(@default_ttl_seconds))
  end

  defp true_key({key, ttl}) when is_integer(ttl), do: key
  defp true_key(key), do: key

  # Cachex.fetch spawns processes which fails ecto sandbox tests
  # defp key_to_ttl_ms({_key, ttl}) when is_integer(ttl), do: ttl * 1000
  # defp key_to_ttl_ms(_), do: @default_ttl_seconds * 1000
  # @impl SanbaseWeb.Graphql.CacheProvider
  # def get_or_store(cache, key, func, cache_modify_middleware) do
  #   {_, result} =
  #     Cachex.fetch(
  #       cache,
  #       true_key(key),
  #       fn ->
  #         result = func.()

  #         handle_fetch_function_result(
  #           cache,
  #           key,
  #           result,
  #           cache_modify_middleware
  #         )
  #       end,
  #       ttl: key_to_ttl_ms(key)
  #     )

  #   result
  # end
  # This is executed from inside the Cachex.fetch/4 function. It is required to
  # return {:ignore, result} or {:commit, result} indicating whether or not the
  # result should be stored in the cache
  # defp handle_fetch_function_result(cache, key, result, cache_modify_middleware) do
  #   case result do
  #     {:middleware, _, _} = tuple ->
  #       # Execute the same function with the new result. When the result is an
  #       # :ok | :error | :nocache tuple it will be handled
  #       middleware_result = cache_modify_middleware.(cache, key, tuple)

  #       handle_fetch_function_result(
  #         cache,
  #         key,
  #         middleware_result,
  #         cache_modify_middleware
  #       )

  #     {:nocache, value} ->
  #       Process.put(:has_nocache_field, true)
  #       {:ignore, value}

  #     {:error, _} = error ->
  #       {:ignore, error}

  #     value ->
  #       cache_item(cache, key, value)
  #       {:ignore, value}
  #   end
  # end
end
