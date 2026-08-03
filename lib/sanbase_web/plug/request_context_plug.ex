defmodule SanbaseWeb.Plug.RequestContextPlug do
  @moduledoc """
  Clears per-request state left over by a previous Cowboy worker request
  and seeds an anonymous `%Sanbase.RequestContext{}` on `conn.assigns`.
  Must run after `Plug.RequestId` (preserves the request id) and before
  any plug that consults the privacy-masking metadata or
  `Sentry.Context.user`.
  """

  @behaviour Plug

  alias Sanbase.RequestContext

  # `Plug.RequestId` takes the client's `x-request-id` validating length only,
  # and downstream it is embedded in ClickHouse `log_comment`.
  @request_id_allowed ~r/[^A-Za-z0-9._:+\/=-]/

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # Selective clears — `Logger.reset_metadata/0` would wipe `:request_id`
    # that `Plug.RequestId` set one plug earlier.
    Logger.metadata(request_context: nil, user_id: nil)
    sanitize_request_id_metadata()
    Sentry.Context.clear_all()

    Plug.Conn.assign(conn, :request_context, RequestContext.anonymous(:graphql))
  end

  defp sanitize_request_id_metadata() do
    case Logger.metadata()[:request_id] do
      request_id when is_binary(request_id) ->
        case String.replace(request_id, @request_id_allowed, "") do
          ^request_id -> :ok
          "" -> Logger.metadata(request_id: nil)
          sanitized -> Logger.metadata(request_id: sanitized)
        end

      _ ->
        :ok
    end
  end
end
