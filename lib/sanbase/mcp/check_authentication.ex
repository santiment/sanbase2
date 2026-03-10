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
    headers = auth_headers(frame)

    if user = frame.assigns[:current_user] do
      response_data = %{
        id: user.id,
        email: user.email,
        subscriptions: Subscription.user_subscription_names(user),
        auth_method: "oauth"
        apikey: MCP.Auth.get_apikey(headers) |> obfuscate_apikey()
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      error = unauthorized_error_msg(headers)
      {:reply, Response.error(Response.tool(), error), frame}
    end
  end

  defp unauthorized_error_msg(headers) do
    specific_error =
      if MCP.Auth.get_header(headers, "authorization") do
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

  defp obfuscate_apikey(nil), do: nil

  defp obfuscate_apikey(apikey) do
    String.duplicate("*", String.length(apikey))
    |> String.replace_prefix("***", String.slice(apikey, 0, 3))
    |> String.replace_suffix("***", String.slice(apikey, -3, 3))
  end

  defp obfuscate_apikey(nil), do: nil

  defp obfuscate_apikey(apikey) do
    String.duplicate("*", String.length(apikey))
    |> String.replace_prefix("***", String.slice(apikey, 0, 3))
    |> String.replace_suffix("***", String.slice(apikey, -3, 3))
  end

  defp auth_headers(frame) do
    context_headers =
      frame
      |> Map.get(:context, %{})
      |> Map.get(:headers)

    cond do
      is_map(context_headers) -> context_headers
      is_list(context_headers) -> context_headers
      match?(%{transport: %{req_headers: _}}, frame) -> frame.transport.req_headers
      true -> []
    end
  end
end
