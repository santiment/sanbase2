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

      # Restore the compile-time defaults when done:
      Application.delete_env(:sanbase, Sanbase.Accounts.ActivityTracesConfig)

  Override values must be booleans; `enabled?/1` raises otherwise.

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
  The full flag map.

  ## Examples

      iex> Map.fetch!(Sanbase.Accounts.ActivityTracesConfig.config(), :hide_logger)
      true
  """
  @spec config() :: %{flag() => boolean()}
  def config(), do: @config

  @doc """
  Whether masking is enabled for `flag`, honoring runtime overrides from
  the application env. Raises for unknown flags and for non-boolean
  runtime overrides.

  The runtime-env indirection is also what keeps the type checker from
  proving the result: with every `@config` value being `true`, a pure
  compile-time lookup makes every call site's conditional provably
  always-true and each one emits a warning.

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.enabled?(:hide_logger)
      true
  """
  @spec enabled?(flag()) :: boolean()
  def enabled?(flag) when is_map_key(@config, flag) do
    :sanbase
    |> Application.get_env(__MODULE__, [])
    |> Keyword.get(flag, Map.fetch!(@config, flag))
    |> case do
      value when is_boolean(value) ->
        value

      other ->
        raise ArgumentError,
              "expected a boolean runtime override for #{inspect(flag)} in the " <>
                "#{inspect(__MODULE__)} application env, got: #{inspect(other)}"
    end
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
end
