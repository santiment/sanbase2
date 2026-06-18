defmodule Sanbase.Accounts.ActivityTracesConfig do
  @moduledoc """
  Per-surface on/off switches for the `activity_traces_hidden` masking
  pipeline.

  Each flag guards exactly one place where an NDA-protected user's
  activity is hidden. Flip a flag to `false` to disable masking on that
  surface — e.g. to debug a specific protected user's request — without
  touching the call site.

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
  Whether masking is enabled for `flag`. Each flag compiles to its own
  clause returning a literal, so this is a constant-time lookup with no
  map access on the hot path.

  ## Examples

      iex> Sanbase.Accounts.ActivityTracesConfig.enabled?(:hide_logger)
      true
  """
  @spec enabled?(flag()) :: boolean()
  for {flag, value} <- @config do
    def enabled?(unquote(flag)), do: unquote(value)
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
