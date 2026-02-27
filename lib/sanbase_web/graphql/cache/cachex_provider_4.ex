# defmodule SanbaseWeb.Graphql.CachexProvider do
#   @behaviour SanbaseWeb.Graphql.CacheProvider
#
#   import Cachex.Spec
#   require Logger
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def start_link(opts) do
#     Cachex.start_link(opts(opts))
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def child_spec(opts) do
#     Supervisor.child_spec({Cachex, opts(opts)}, id: Keyword.fetch!(opts, :id))
#   end
#
#   @default_max_entries 2_000_000
#   @default_reclaim_ratio 0.3
#   @default_limit_check_interval_ms 5000
#   @default_ttl_seconds 300
#   @default_expiration_interval_seconds 10
#
#   defp opts(opts) do
#     max_entries = Keyword.get(opts, :max_entries, @default_max_entries)
#     reclaim = Keyword.get(opts, :reclaim, @default_reclaim_ratio)
#
#     limit_interval_ms =
#       Keyword.get(opts, :limit_check_interval_ms, @default_limit_check_interval_ms)
#
#     default_ttl = Keyword.get(opts, :default_ttl_seconds, @default_ttl_seconds)
#
#     expiration_interval =
#       Keyword.get(opts, :expiration_interval_seconds, @default_expiration_interval_seconds)
#
#     ensure_opts_ets()
#     :ets.insert(:sanbase_graphql_cachex_opts, {Keyword.fetch!(opts, :name), default_ttl})
#
#     [
#       name: Keyword.fetch!(opts, :name),
#       hooks: [
#         hook(
#           module: Cachex.Limit.Scheduled,
#           args: {
#             max_entries,
#             [reclaim: reclaim],
#             [frequency: limit_interval_ms]
#           }
#         )
#       ],
#       expiration:
#         expiration(
#           default: :timer.seconds(default_ttl),
#           interval: :timer.seconds(expiration_interval),
#           lazy: true
#         )
#     ]
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def size(cache) do
#     {:ok, bytes_size} = Cachex.inspect(cache, {:memory, :bytes})
#     (bytes_size / (1024 * 1024)) |> Float.round(2)
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def count(cache) do
#     {:ok, count} = Cachex.size(cache)
#     count
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def clear_all(cache) do
#     {:ok, _} = Cachex.clear(cache)
#     :ok
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def get(cache, key) do
#     case Cachex.get(cache, true_key(key)) do
#       {:ok, compressed_value} when is_binary(compressed_value) ->
#         decompress_value(compressed_value)
#
#       _ ->
#         nil
#     end
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def store(cache, key, value) do
#     case value do
#       {:error, _} ->
#         :ok
#
#       {:nocache, _} ->
#         Process.put(:do_not_cache_query, true)
#         :ok
#
#       _ ->
#         cache_item(cache, key, value)
#     end
#   end
#
#   @impl SanbaseWeb.Graphql.CacheProvider
#   def get_or_store(cache, key, func, cache_modify_middleware) do
#     true_key = true_key(key)
#     ttl = ttl_ms(cache, key)
#
#     result =
#       Cachex.fetch(cache, true_key, fn ->
#         case func.() do
#           {:ok, _} = ok_tuple ->
#             {:commit, compress_value(ok_tuple), [expire: ttl]}
#
#           {:error, _} = error ->
#             {:ignore, error}
#
#           {:nocache, value} ->
#             # Do not put the :do_not_cache_query flag here as is
#             # is executed inside a Courier process. Set it afterwards
#             # when handling the result
#             {:ignore, {:nocache, value}}
#
#           {:middleware, _middleware_module, _args} = tuple ->
#             {:ignore, cache_modify_middleware.(cache, key, tuple)}
#         end
#       end)
#
#     case result do
#       {:commit, compressed} when is_binary(compressed) ->
#         decompress_value(compressed)
#
#       {:ok, compressed} when is_binary(compressed) ->
#         decompress_value(compressed)
#
#       {:error, error} ->
#         # Transforms like :no_cache -> "Specified cache not running"
#         error_msg = if is_atom(error), do: Cachex.Error.long_form(error), else: error
#         {:error, error_msg}
#
#       {:ignore, {:error, error}} ->
#         # Transforms like :no_cache -> "Specified cache not running"
#         error_msg = if is_atom(error), do: Cachex.Error.long_form(error), else: error
#         {:error, error_msg}
#
#       {:ignore, {:nocache, value}} ->
#         Process.put(:do_not_cache_query, true)
#         value
#
#       {:ignore, value} ->
#         value
#     end
#   end
#
#   defp ttl_ms(_cache, {_key, ttl}) when is_integer(ttl), do: :timer.seconds(ttl)
#   defp ttl_ms(cache, _key), do: :timer.seconds(default_ttl_seconds(cache))
#
#   defp cache_item(cache, {key, ttl}, value) when is_integer(ttl) do
#     Cachex.put(cache, key, compress_value(value), expire: :timer.seconds(ttl))
#   end
#
#   defp cache_item(cache, key, value) do
#     Cachex.put(cache, key, compress_value(value),
#       expire: :timer.seconds(default_ttl_seconds(cache))
#     )
#   end
#
#   defp default_ttl_seconds(cache) do
#     case :ets.lookup(:sanbase_graphql_cachex_opts, cache) do
#       [{^cache, ttl}] -> ttl
#       [] -> @default_ttl_seconds
#     end
#   rescue
#     _ ->
#       Logger.error(
#         "CachexProvider: Could not get default TTL from ETS for cache #{cache}, using default #{@default_ttl_seconds}"
#       )
#
#       @default_ttl_seconds
#   end
#
#   defp ensure_opts_ets() do
#     case :ets.whereis(:sanbase_graphql_cachex_opts) do
#       :undefined ->
#         try do
#           :ets.new(:sanbase_graphql_cachex_opts, [:named_table, :public, :set])
#         catch
#           :error, {:badarg, _} -> :ok
#           :error, :badarg -> :ok
#           :error, %ArgumentError{} -> :ok
#         end
#
#       _ ->
#         :ok
#     end
#
#     :ok
#   end
#
#   defp true_key({key, ttl}) when is_integer(ttl), do: key
#   defp true_key(key), do: key
#
#   defp compress_value(value) do
#     value
#     |> :erlang.term_to_binary()
#     |> :zlib.gzip()
#   end
#
#   defp decompress_value(value) do
#     value
#     |> :zlib.gunzip()
#     |> :erlang.binary_to_term()
#   end
# end
