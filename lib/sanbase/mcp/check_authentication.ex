defmodule Sanbase.MCP.CheckAuthentication do
  @moduledoc "Return information about the authenticated user, if any"
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Billing.Subscription
  alias Sanbase.MCP

  schema do
  end

  @impl true
  def execute(_params, frame) do
    if user = frame.assigns[:current_user] do
      response_data = %{
        id: user.id,
        email: user.email,
        subscriptions: Subscription.user_subscription_names(user),
        auth_method: "oauth"
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      error = unauthorized_error_msg(frame)
      {:reply, Response.error(Response.tool(), error), frame}
    end
  end

  defp unauthorized_error_msg(frame) do
    specific_error =
      if MCP.Auth.has_authorization_header?(frame.transport.req_headers) do
        "Authorization header is present, but the OAuth token is invalid or expired."
      else
        "No Authorization header provided."
      end

    """
    Unauthorized.

    #{specific_error}

    Authenticate via OAuth 2.0 to obtain a Bearer token.
    The header must be: Authorization: Bearer <your_oauth_token>
    """
  end
end
