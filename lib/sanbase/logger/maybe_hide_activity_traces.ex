defmodule Sanbase.Logger.MaybeHideActivityTraces do
  @moduledoc """
  `:logger` filter that protects log entries for users with
  `activity_traces_hidden` (NDA-protected).

  Keyed on the `:request_context` Logger metadata struct set at every
  request edge (`AuthPlug`, MCP `with_logger_metadata`). For ANY log
  event emitted during a protected user's request, this filter:

    1. Drops sensitive keys from the event's meta — specifically
       `:remote_ip`, `:query`, `:san_balance` — so they don't appear in
       the rendered log line. `:request_id`, `:user_id`, and
       `:complexity` are kept so the line stays correlatable and load
       characteristics remain auditable.

    2. If the message starts with `"ABSINTHE"` (the prefix emitted by
       `Absinthe.Logger.log_run/2` for the GraphQL document) or
       `"QUERY"` (the prefix emitted by `Ecto.Adapters.SQL` for every
       repo query), rewrites `msg` to a short redaction breadcrumb that
       names the user and the reason. This covers both the GraphQL doc
       and the underlying ClickHouse/Postgres SQL text.

  ## Why no try/rescue

  Primary filters that raise are unregistered by OTP. To stay safe
  without a rescue, every code path here is total: we only introspect
  msg shapes we can match without calling `IO.iodata_to_binary/1` or
  `:io_lib.format/2` (both can raise on malformed input), and treat
  every other shape as `:other` — meta gets scrubbed, msg passes
  through unchanged. Absinthe + Ecto both produce `{:string, iodata}`
  events, so the narrower match is sufficient in practice.

  Return values follow `:logger.filter_return/0`: a rewritten
  `log_event()` map replaces the original, `:ignore` leaves it
  untouched. `:stop` is never returned — full suppression would also
  drop request_id/duration and make protected-user volume invisible to
  ops.
  """

  alias Sanbase.RequestContext

  # Subset of the allowlist in `config :logger, :console, metadata: ...`
  # that can identify the customer or reveal the document. Kept in sync
  # with that allowlist; adding a new sensitive meta key to the logger
  # config means adding it here too.
  @sensitive_meta_keys [:remote_ip, :query, :san_balance]

  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(event, extra) do
    do_filter(event, extra)
  catch
    # NOT a defensive rescue for input shapes — those are already
    # exhaustively pattern-matched below. This catches the transient
    # `:undef` that OTP raises if a log event arrives during a hot code
    # reload (after `code:purge/1`, before `code:load_binary/3`). Without
    # it OTP would unregister the filter permanently and protected users
    # would silently lose log redaction until the BEAM restarts.
    :error, :undef -> :ignore
  end

  defp do_filter(
         %{
           meta: %{request_context: %RequestContext{activity_traces_hidden: true} = ctx} = meta,
           msg: msg
         } = event,
         _extra
       ) do
    event = %{event | meta: Map.drop(meta, @sensitive_meta_keys)}

    case msg_kind(msg) do
      :absinthe -> %{event | msg: {:string, absinthe_redaction(ctx)}}
      :ecto -> %{event | msg: {:string, ecto_redaction(ctx)}}
      :other -> event
    end
  end

  defp do_filter(_event, _extra), do: :ignore

  defp absinthe_redaction(ctx) do
    "GraphQL request received from user_id=#{ctx.user_id || "anonymous"} — document hidden (activity_traces_hidden)" <>
      ctx_hint(ctx)
  end

  defp ecto_redaction(ctx) do
    "Repo query for user_id=#{ctx.user_id || "anonymous"} — SQL body hidden (activity_traces_hidden)" <>
      ctx_hint(ctx)
  end

  # Per-request context fields that hint at WHERE the request came from
  # without revealing WHAT it queried. All four are non-sensitive
  # metadata captured at the edge (`AuthPlug` / MCP `with_logger_metadata`).
  # Nil fields are skipped so the suffix stays compact.
  defp ctx_hint(%RequestContext{} = ctx) do
    parts =
      [
        origin: ctx.origin,
        auth: ctx.auth_method,
        product: ctx.product_code,
        client: ctx.client
      ]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.map(fn {k, v} -> "#{k}=#{v}" end)

    case parts do
      [] -> ""
      _ -> " — " <> Enum.join(parts, " ")
    end
  end

  # Each clause matches only on shapes we can inspect without raising.
  # Anything else falls through to `:other` — meta still gets scrubbed,
  # msg is left untouched.

  defp msg_kind({:string, msg}), do: classify(msg)
  defp msg_kind(_), do: :other

  defp classify(bin) when is_binary(bin), do: prefix_kind(bin)

  defp classify([head | _]) when is_binary(head), do: prefix_kind(head)

  defp classify(_), do: :other

  defp prefix_kind(bin) do
    cond do
      String.starts_with?(bin, "ABSINTHE") -> :absinthe
      String.starts_with?(bin, "QUERY") -> :ecto
      true -> :other
    end
  end
end
