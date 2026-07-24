defmodule Sanbase.Accounts.ActivityTracesConfig do
  @moduledoc """
  Per-surface on/off switches for the `activity_traces_hidden` masking
  pipeline.

  Each flag guards exactly one place where an NDA-protected user's
  activity is hidden. To disable masking on one surface without touching
  the call site, either flip the flag in `@config` or override it at
  runtime. Both the application env and the reload are node-local, so on
  a multi-node deployment repeat this on every node that matters:

      # Disable one surface (for every protected request on this node):
      Application.put_env(:sanbase, Sanbase.Accounts.ActivityTracesConfig,
        hide_logger: false
      )

      # Apply it immediately (reads are cached, see below):
      Sanbase.Accounts.ActivityTracesConfig.reload()

      # Restore the compile-time defaults when done:
      Application.delete_env(:sanbase, Sanbase.Accounts.ActivityTracesConfig)
      Sanbase.Accounts.ActivityTracesConfig.reload()

  Override values must be booleans and keys must be known flags;
  anything else raises when the override is (re)loaded.

  ## Caching

  `enabled?/1` does not read the application env directly. The resolved
  flag map (defaults merged with the override) is cached via
  `Sanbase.Cache.PersistentTermTtl`, so the hot path is a copy-free,
  lock-free read. The cache entry expires after 60 minutes and is
  rebuilt lazily on the next read; call `reload/0` to rebuild it
  immediately.

  Masking at a surface applies only when BOTH conditions hold:

    1. the user is protected
       (`Sanbase.RequestContext.activity_traces_hidden?/1`), and
    2. the surface's flag here is enabled.

  Call sites that have a `RequestContext` should use `hidden?/2`, which
  combines both checks. The logger filter and the Intercom batch export
  establish "is protected" by other means and only need `enabled?/1`.
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
    # Skip all Intercom-bound exports: the CRM contact/stats batch
    # (sanbase_user_intercom_attributes) and per-request trackEvents
    # writes (user_events Kafka topic + Postgres).
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
  The compile-time default flag map. Runtime overrides are NOT applied
  here — use `enabled?/1` for the effective value.

  ## Examples

      iex> Map.fetch!(Sanbase.Accounts.ActivityTracesConfig.config(), :hide_logger)
      true
  """
  @spec config() :: %{flag() => boolean()}
  def config(), do: @config

  @doc """
  Whether masking is enabled for `flag`, honoring runtime overrides from
  the application env (through the cache). Raises for unknown flags, and
  raises `ArgumentError` when a rebuild finds an invalid override
  (unknown key or non-boolean value).

  The cache indirection is also what keeps the type checker from proving
  the result: with every `@config` value being `true`, a pure
  compile-time lookup makes every call site's conditional provably
  always-true and each one emits a warning.

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
  should use. Non-struct / `nil` `ctx` is treated as not protected.

  The context check runs first: it is a bare struct-field read, so the
  majority (non-protected) traffic short-circuits without touching the
  config cache.

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.hidden?(:hide_logger, nil)
      false
  """
  @spec hidden?(flag(), RequestContext.t() | term()) :: boolean()
  def hidden?(flag, ctx) when is_map_key(@config, flag) do
    RequestContext.activity_traces_hidden?(ctx) and enabled?(flag)
  end

  @doc """
  Rebuild the resolved flag map from the compile-time defaults and the
  application env override, store it in the cache, and reset its TTL.

  Call this after `Application.put_env/3` / `Application.delete_env/2`
  to apply the change immediately instead of waiting for the TTL to
  expire. Node-local, like the env itself. Raises `ArgumentError` when
  the override contains an unknown flag or a non-boolean value.
  """
  @spec reload() :: :ok
  def reload() do
    PersistentTermTtl.store(@pt_key, @ttl_ms, fn -> {:store, build_resolved_config()} end)
    :ok
  end

  @doc """
  Back-dates the cached entry past the TTL so the next read rebuilds it
  from the application env. Used by tests; also handy for ops.
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
