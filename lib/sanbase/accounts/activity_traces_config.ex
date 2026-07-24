defmodule Sanbase.Accounts.ActivityTracesConfig do
  @moduledoc """
  Per-surface on/off switches for the `activity_traces_hidden` masking
  pipeline.

  Each flag guards exactly one place where an NDA-protected user's
  activity is hidden. To disable masking on one surface without touching
  the call site, either flip the flag in `@config` or override it at
  runtime. The runtime override mutates the global application env, so
  it affects ALL protected requests on the node — not just the one being
  debugged — until it is removed:

      # Disable one surface (node-wide, for every protected request):
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
  flag map (defaults merged with the override) is cached in
  `:persistent_term`, so the hot path is a copy-free, lock-free read.
  The cache entry expires after #{div(:timer.minutes(60), 60_000)}
  minutes and is rebuilt lazily on the next read; call `reload/0` to
  rebuild it immediately. The cache is an internal detail of this
  module — nothing outside it should touch the persistent-term key.

  Masking at a surface applies only when BOTH conditions hold:

    1. the user is protected
       (`Sanbase.RequestContext.activity_traces_hidden?/1`), and
    2. the surface's flag here is enabled.

  Call sites that have a `RequestContext` should use `hidden?/2`, which
  combines both checks. The logger filter and the Intercom batch export
  establish "is protected" by other means and only need `enabled?/1`.
  """

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

  # Cached resolved config: {resolved_map, expires_at_monotonic_ms}.
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
  the application env (through the persistent-term cache). Raises for
  unknown flags, and raises `ArgumentError` when a rebuild finds an
  invalid override (unknown key or non-boolean value).

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

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.hidden?(:hide_logger, nil)
      false
  """
  @spec hidden?(flag(), RequestContext.t() | term()) :: boolean()
  def hidden?(flag, ctx) do
    enabled?(flag) and RequestContext.activity_traces_hidden?(ctx)
  end

  @doc """
  Rebuild the resolved flag map from the compile-time defaults and the
  application env override, store it in the cache, and reset its TTL.

  Call this after `Application.put_env/3` / `Application.delete_env/2`
  to apply the change immediately instead of waiting for the TTL to
  expire. Raises `ArgumentError` when the override contains an unknown
  flag or a non-boolean value.
  """
  @spec reload() :: :ok
  def reload() do
    _resolved = store_resolved_config()
    :ok
  end

  defp resolved_config() do
    case :persistent_term.get(@pt_key, nil) do
      {resolved, expires_at} ->
        if System.monotonic_time(:millisecond) < expires_at,
          do: resolved,
          else: store_resolved_config()

      nil ->
        store_resolved_config()
    end
  end

  # Concurrent readers hitting an expired entry may race several puts;
  # each stores an equally fresh map, so last-write-wins is harmless.
  defp store_resolved_config() do
    resolved = build_resolved_config()
    expires_at = System.monotonic_time(:millisecond) + @ttl_ms
    :persistent_term.put(@pt_key, {resolved, expires_at})
    resolved
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
