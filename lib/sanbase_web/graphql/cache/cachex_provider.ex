defmodule SanbaseWeb.Graphql.CachexProvider do
  @behaviour SanbaseWeb.Graphql.CacheProvider

  import Cachex.Spec

  @default_max_entries 2_000_000
  @default_reclaim_ratio 0.3
  @default_ttl_seconds 300
  @default_expiration_interval_seconds 10

  @impl SanbaseWeb.Graphql.CacheProvider
  def start_link(opts) do
    Cachex.start_link(opts(opts))
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def child_spec(opts) do
    Supervisor.child_spec({Cachex, opts(opts)}, id: Keyword.fetch!(opts, :id))
  end

  defp opts(opts) do
    max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
    reclaim = Keyword.get(opts, :reclaim, @default_reclaim_ratio)
    default_ttl = Keyword.get(opts, :default_ttl_seconds, @default_ttl_seconds)

    expiration_interval =
      Keyword.get(opts, :expiration_interval_seconds, @default_expiration_interval_seconds)

    [
      name: Keyword.fetch!(opts, :name),
      # Cachex.Limit.Evented mirrors v3's Cachex.Policy.LRW: it hooks every
      # write and prunes reactively, keeping ETS bounded near max_entries.
      hooks: [
        hook(module: Cachex.Limit.Evented, args: {max_entries, [reclaim: reclaim]})
      ],
      expiration:
        expiration(
          default: :timer.seconds(default_ttl),
          interval: :timer.seconds(expiration_interval),
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
      {:ok, compressed} when is_binary(compressed) -> decompress_value(compressed)
      _ -> nil
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
        Cachex.put(cache, true_key(key), compress_value(value), put_opts(key))
        :ok
    end
  end

  @impl SanbaseWeb.Graphql.CacheProvider
  def get_or_store(cache, key, func, cache_modify_middleware) do
    true_key = true_key(key)

    case Cachex.get(cache, true_key) do
      {:ok, compressed} when is_binary(compressed) ->
        decompress_value(compressed)

      _ ->
        # Per-key stampede protection via ConCache.Lock. The fallback runs in
        # the caller process so Absinthe's Dataloader batching and process-dict
        # signals (e.g. :do_not_cache_query) are preserved. We piggyback on the
        # already-running :sanbase_cache ConCache instance for its lock pids; no
        # data is stored in it.
        ConCache.isolated(Sanbase.Cache.name(), {__MODULE__, true_key}, fn ->
          case Cachex.get(cache, true_key) do
            {:ok, compressed} when is_binary(compressed) ->
              decompress_value(compressed)

            _ ->
              execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware)
          end
        end)
    end
  end

  defp execute_and_maybe_cache(cache, key, true_key, func, cache_modify_middleware) do
    case safe_invoke(func) do
      {:ok, _} = ok_tuple ->
        Cachex.put(cache, true_key, compress_value(ok_tuple), put_opts(key))
        ok_tuple

      {:error, _} = error ->
        error

      {:nocache, value} ->
        Process.put(:do_not_cache_query, true)
        value

      {:middleware, _, _} = tuple ->
        cache_modify_middleware.(cache, key, tuple)
    end
  end

  # Match Cachex.fetch's behavior: a raise in the fallback fn becomes an
  # `{:error, message}` tuple so concurrent callers don't all crash. The
  # resolver layer treats errors as uncached.
  defp safe_invoke(func) do
    func.()
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp put_opts({_key, ttl}) when is_integer(ttl), do: [expire: :timer.seconds(ttl)]
  defp put_opts(_key), do: []

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
