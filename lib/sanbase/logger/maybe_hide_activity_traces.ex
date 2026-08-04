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

  ## Failure handling

  `:logger` unregisters a primary filter permanently the first time it
  raises, silently disabling redaction until the node restarts. Guards:
  every code path here is total (no `IO.iodata_to_binary/1` or
  `:io_lib.format/2`, both of which can raise — unmatched shapes pass
  through with scrubbed meta); `install!/0` pre-loads `@runtime_modules`;
  and the `ActivityTracesFilterWatchdog` re-installs the filter if OTP
  drops it anyway — the only cover for this module itself being unloaded.

  Return values follow `:logger.filter_return/0`: a rewritten
  `log_event()` map replaces the original, `:ignore` leaves it
  untouched. `:stop` is never returned — full suppression would also
  drop request_id/duration and make protected-user volume invisible to
  ops.
  """

  alias Sanbase.RequestContext
  alias Sanbase.Accounts.ActivityTracesConfig

  @filter_id :sanbase_maybe_hide_activity_traces

  # Modules `filter/2` calls at runtime — an unloaded one raises `:undef`
  # out of the filter. `Sanbase.RequestContext` appears only in patterns.
  @runtime_modules [
    __MODULE__,
    Sanbase.Accounts.ActivityTracesConfig,
    Sanbase.Cache.PersistentTermTtl
  ]

  # Subset of the allowlist in `config :logger, :console, metadata: ...`
  # that can identify the customer or reveal the document. Kept in sync
  # with that allowlist; adding a new sensitive meta key to the logger
  # config means adding it here too.
  @sensitive_meta_keys [:remote_ip, :query, :san_balance]

  @doc "The `:logger` filter id this module registers itself under."
  @spec filter_id() :: atom()
  def filter_id(), do: @filter_id

  @doc """
  Register the filter as a `:logger` primary filter, first loading every
  module `filter/2` calls at runtime. Idempotent; raises on failure —
  a silently missing filter means protected users' queries reach the logs.
  """
  @spec install!() :: :ok
  def install!() do
    Code.ensure_all_loaded!(@runtime_modules)

    case :logger.add_primary_filter(@filter_id, {&__MODULE__.filter/2, []}) do
      :ok ->
        :ok

      {:error, {:already_exist, _}} ->
        :ok

      {:error, reason} ->
        raise "Failed to register the #{inspect(@filter_id)} logger filter: #{inspect(reason)}"
    end
  end

  @doc "Whether the primary filter is currently registered."
  @spec installed?() :: boolean()
  def installed?() do
    %{filters: filters} = :logger.get_primary_config()
    List.keymember?(filters, @filter_id, 0)
  end

  @spec filter(:logger.log_event(), term()) :: :logger.filter_return()
  def filter(event, extra) do
    do_filter(event, extra)
  catch
    # An `:undef` from a callee purged mid-recompile would make OTP drop
    # the filter permanently. This cannot cover THIS module being unloaded
    # (the `:undef` fires at the call site); the watchdog covers that.
    :error, :undef -> :ignore
  end

  defp do_filter(
         %{
           meta: %{request_context: %RequestContext{activity_traces_hidden: true} = ctx} = meta,
           msg: msg
         } = event,
         _extra
       ) do
    if ActivityTracesConfig.enabled?(:hide_logger) do
      event = %{event | meta: Map.drop(meta, @sensitive_meta_keys)}

      case msg_kind(msg) do
        :absinthe -> %{event | msg: {:string, absinthe_redaction(ctx)}}
        :ecto -> %{event | msg: {:string, ecto_redaction(ctx)}}
        :other -> event
      end
    else
      :ignore
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
