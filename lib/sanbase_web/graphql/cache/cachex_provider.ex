defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @default_ttl_seconds 300

  @max_lock_acquired_time_ms 60_000

  import Cachex.Spec

  @compile inline: [
             execute_cache_miss_function: 4,
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
      {:ok, compressed_value} when is_binary(compressed_value) ->
        decompress_value(compressed_value)

      _ ->
        nil
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
        cache_item(cache, key, value)
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)

    case Cachex.get(cache, true_key) do
      {:ok, compressed_value} when is_binary(compressed_value) ->
        decompress_value(compressed_value)

      _ ->
        execute_cache_miss_function(cache, key, func, cache_modify_middleware)
    end
  end

  defp execute_cache_miss_function(cache, key, func, cache_modify_middleware) do
    # This is the only place where we need to have the transactional get_or_store
    # mechanism. Cachex.fetch! is running in multiple processes, which causes issues
    # when testing. Cachex.transaction has a non-configurable timeout. We actually
    # can achieve the required behavior by manually getting and realeasing the lock.
    # The transactional guarantees are not needed.
    cache_record = Cachex.Services.Overseer.ensure(cache)

    # Start a process that will handle the unlock in case this process terminates
    # without releasing the lock. The process is not linked to the current one so
    # it can continue to live and do its job even if this process terminates.
    {:ok, unlocker_pid} =
      __MODULE__.Unlocker.start(max_lock_acquired_time_ms: @max_lock_acquired_time_ms)

    unlock_fun = fn -> Cachex.Services.Locksmith.unlock(cache_record, [true_key(key)]) end

    try do
      true = obtain_lock(cache_record, [true_key(key)])
      _ = GenServer.cast(unlocker_pid, {:unlock_after, unlock_fun})

      case Cachex.get(cache, true_key(key)) do
        {:ok, compressed_value} when is_binary(compressed_value) ->
          # First check if the result has not been stored while waiting for the lock.
          decompress_value(compressed_value)

        _ ->
          handle_execute_cache_miss_function(
            cache,
            key,
            _result = func.(),
            cache_modify_middleware
          )
      end
    after
      true = unlock_fun.()
      # We expect the process to unlock only in case we don't reach here for some reason.
      # If we're here we can kill the process. If the process has already unlocked
      _ = GenServer.cast(unlocker_pid, :stop)
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
        sleep_ms = Enum.min([sleep_ms, 2000])

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
        cache_item(cache, key, ok_tuple)
        ok_tuple
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
    Cachex.put(cache, key, compress_value(value), ttl: :timer.seconds(ttl))
  end

  defp cache_item(cache, key, value) do
    Cachex.put(cache, key, compress_value(value), ttl: :timer.seconds(@default_ttl_seconds))
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
