defmodule Sanbase.Accounts.ActivityTracesConfig do
  @moduledoc """
  Per-surface on/off switches for the `activity_traces_hidden` masking
  pipeline.

  Each flag guards exactly one place where an NDA-protected user's
  activity is hidden. Defaults live in `@config`; a flag can be
  overridden at runtime (node-local):

      Application.put_env(:sanbase, Sanbase.Accounts.ActivityTracesConfig,
        hide_logger: false
      )
      Sanbase.Accounts.ActivityTracesConfig.reload()

  The resolved map is cached via `Sanbase.Cache.PersistentTermTtl` for
  60 minutes; `reload/0` applies env changes immediately. Invalid
  overrides (unknown flag or non-boolean value) raise on (re)load.

  Masking applies only when the user is protected
  (`Sanbase.RequestContext.activity_traces_hidden?/1`) AND the surface's
  flag is enabled. Use `hidden?/2` where a `RequestContext` is
  available, `enabled?/1` where "is protected" is established otherwise.
  """

  alias Sanbase.Cache.PersistentTermTtl
  alias Sanbase.RequestContext

  @config %{
    # OTP logger filter: rewrite Absinthe/Ecto log lines to a breadcrumb.
    hide_logger: true,
    # ClickHouse: append `log_queries = 0` so system.query_log skips the query.
    hide_ch_query_log: true,
    # ClickHouse: replace error-log Reason/stacktrace with a breadcrumb.
    hide_ch_error_logs: true,
    # ChatResolver: redact prompt/response content in request/response logs.
    hide_chat_logs: true,
    # Kafka api_call_data: mask query/selector/token/ip/sizes in the export.
    hide_kafka_api_call_data: true,
    # Skip Intercom-bound exports: attributes batch + trackEvents writes.
    hide_intercom: true,
    # MCP: mask tool_name/params/client/session in tool_invocations.
    hide_mcp_tool_invocations: true,
    # Dev-only: skip the PRINT_INTERPOLATED_CLICKHOUSE_SQL console dump.
    hide_interpolated_sql: true
  }

  @pt_key {__MODULE__, :resolved_config}
  @ttl_ms :timer.minutes(60)

  @type flag ::
          :hide_logger
          | :hide_ch_query_log
          | :hide_ch_error_logs
          | :hide_chat_logs
          | :hide_kafka_api_call_data
          | :hide_intercom
          | :hide_mcp_tool_invocations
          | :hide_interpolated_sql

  @doc """
  The compile-time default flag map, without runtime overrides — use
  `enabled?/1` for the effective value.

  ## Examples

      iex> Map.fetch!(Sanbase.Accounts.ActivityTracesConfig.config(), :hide_logger)
      true
  """
  @spec config() :: %{flag() => boolean()}
  def config(), do: @config

  @doc """
  Whether masking is enabled for `flag`, honoring runtime overrides.
  Raises on unknown flags, and `ArgumentError` when a cache rebuild
  finds an invalid override.

  Reading through the cache (not the `@config` literals) also keeps the
  type checker from proving call-site conditionals always-true and
  warning about them.

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.enabled?(:hide_logger)
      true
  """
  @spec enabled?(flag()) :: boolean()
  def enabled?(flag) when is_map_key(@config, flag) do
    Map.fetch!(resolved_config(), flag)
  end

  @doc """
  True when `ctx` identifies a protected user AND masking for `flag` is
  enabled. The single check every `RequestContext`-aware masking site
  should use. Non-struct / `nil` `ctx` is treated as not protected. The
  context is checked first so non-protected traffic skips the config
  cache.

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.hidden?(:hide_logger, nil)
      false
  """
  @spec hidden?(flag(), RequestContext.t() | term()) :: boolean()
  def hidden?(flag, ctx) when is_map_key(@config, flag) do
    RequestContext.activity_traces_hidden?(ctx) and enabled?(flag)
  end

  @doc """
  Rebuild the cached flag map from the defaults plus the application
  env override, resetting the TTL. Call after `Application.put_env/3` /
  `delete_env/2` to apply the change immediately. Node-local. Raises
  `ArgumentError` on an invalid override.
  """
  @spec reload() :: :ok
  def reload() do
    PersistentTermTtl.store(@pt_key, @ttl_ms, fn -> {:store, build_resolved_config()} end)
    :ok
  end

  @doc """
  Expire the cached entry so the next read rebuilds it. For tests and
  ops.
  """
  @spec expire_cache!() :: :ok
  def expire_cache!(), do: PersistentTermTtl.expire(@pt_key)

  defp resolved_config() do
    PersistentTermTtl.get_or_store(@pt_key, @ttl_ms, fn -> {:store, build_resolved_config()} end)
  end

  defp build_resolved_config() do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Enum.reduce(@config, fn
      {flag, value}, acc when is_map_key(@config, flag) and is_boolean(value) ->
        Map.put(acc, flag, value)

      {flag, value}, _acc ->
        raise ArgumentError,
              "invalid runtime override #{inspect(flag)} => #{inspect(value)} " <>
                "in the #{inspect(__MODULE__)} application env. Overrides must " <>
                "use known flags (#{Enum.map_join(Map.keys(@config), ", ", &inspect/1)}) " <>
                "and boolean values."
    end)
  end
end
