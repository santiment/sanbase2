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

  @impl true
  def init(opts), do: opts

  @impl true
  def call(conn, _opts) do
    # Selective clears — `Logger.reset_metadata/0` would wipe `:request_id`
    # that `Plug.RequestId` set one plug earlier.
    Logger.metadata(request_context: nil, hide_user_activity_traces: nil, user_id: nil)
    Sentry.Context.clear_all()

    Plug.Conn.assign(conn, :request_context, RequestContext.anonymous(:graphql))
  end
end
