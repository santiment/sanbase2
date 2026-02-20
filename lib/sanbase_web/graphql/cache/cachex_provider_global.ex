defmodule SanbaseWeb.Graphql.CachexProviderGlobal do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @default_ttl_seconds 300
  @global_lock_nodes [node()]

  import Cachex.Spec

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
        Process.put(:do_not_cache_query, true)
        :ok

      _ ->
        cache_item(cache, key, value)
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)
    # The self() is the LockRequesterId, the resource is uniquely
    # identified by the first element of the tuple. Using the pid
    # here DOES NOT make it so different callers execute the function
    # at the same time.
    lock_key = {{cache, true_key}, self()}

    case Cachex.get(cache, true_key) do
      {:ok, compressed_value} when is_binary(compressed_value) ->
        decompress_value(compressed_value)

      _ ->
        :global.trans(
          lock_key,
          fn ->
            case Cachex.get(cache, true_key) do
              {:ok, compressed_value} when is_binary(compressed_value) ->
                decompress_value(compressed_value)

              _ ->
                execute_cache_miss(cache, key, func, cache_modify_middleware)
            end
          end,
          @global_lock_nodes
        )
    end
  end

  defp execute_cache_miss(cache, key, func, cache_modify_middleware) do
    result =
      try do
        func.()
      rescue
        e -> {:error, Exception.message(e)}
      catch
        kind, reason -> {:error, "#{kind}: #{inspect(reason)}"}
      end

    case result do
      {:ok, _} = ok_tuple ->
        cache_item(cache, key, ok_tuple)
        ok_tuple

      {:error, _} = error ->
        error

      {:nocache, value} ->
        Process.put(:do_not_cache_query, true)
        value

      {:middleware, _middleware_module, _args} = tuple ->
        cache_modify_middleware.(cache, key, tuple)
    end
  end

  defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
    Cachex.put(cache, key, compress_value(value), expire: :timer.seconds(ttl))
  end

  defp cache_item(cache, key, value) do
    Cachex.put(cache, key, compress_value(value), expire: :timer.seconds(@default_ttl_seconds))
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
