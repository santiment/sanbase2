defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider
  @default_ttl_seconds 300

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
    ttl = ttl_ms(key)

    # Cachex.fetch/4 routes cache misses through the Courier service, which
    # ensures that for a given key only one process executes the fallback
    # function at a time. All other concurrent callers for the same key are
    # held until the result is ready and then receive that same result.
    result =
      Cachex.fetch(cache, true_key, fn ->
        case func.() do
          {:ok, _} = ok_tuple ->
            {:commit, compress_value(ok_tuple), [expire: ttl]}

          {:error, _} = error ->
            {:ignore, error}

          {:nocache, value} ->
            Process.put(:do_not_cache_query, true)
            {:ignore, {:nocache, value}}

          {:middleware, _middleware_module, _args} = tuple ->
            {:ignore, cache_modify_middleware.(cache, key, tuple)}
            |> dbg()
        end
      end)

    case result do
      {:commit, compressed} when is_binary(compressed) ->
        decompress_value(compressed)

      {:ok, compressed} when is_binary(compressed) ->
        decompress_value(compressed)

      {:error, %Cachex.Error{message: message}} ->
        {:error, message}

      {:error, _} = error ->
        error

      {:ignore, {:nocache, value}} ->
        Process.put(:do_not_cache_query, true)
        value

      {:ignore, value} ->
        value
    end
  end

  defp ttl_ms({_key, ttl}) when is_integer(ttl), do: :timer.seconds(ttl)
  defp ttl_ms(_key), do: :timer.seconds(@default_ttl_seconds)

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
