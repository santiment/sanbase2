defmodule Sanbase.MCP.CheckAuthentication do
  @moduledoc "Return information about the authenticated user, if any"
  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.Billing.Subscription
  alias Sanbase.MCP

  schema do
    # No arguments
  end

  @impl true
  def execute(_params, frame) do
    headers = auth_headers(frame)
    auth_method = MCP.Auth.get_auth_method(headers)

    if user = frame.assigns[:current_user] do
      response_data = %{
        id: user.id,
        email: user.email,
        subscriptions: Subscription.user_subscription_names(user),
        auth_method: auth_method,
        apikey: auth_method |> apikey_for_method(headers) |> obfuscate_apikey()
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      error = unauthorized_error_msg(headers)
      {:reply, Response.error(Response.tool(), error), frame}
    end
  end

  defp unauthorized_error_msg(headers) do
    specific_error =
      if MCP.Auth.has_authorization_header?(headers) do
        "Authorization header is present, but invalid."
      else
        "No Authorization header provided."
      end

    """
    Unauthorized.

    #{specific_error}

    Supported authentication methods:
    - OAuth 2.0: Authorization: Bearer <your_oauth_token>
    - API key:   Authorization: Apikey <your_api_key>

    Note: MCP Inspector automatically prepends "Bearer" to the header value.
    """
  end

  defp apikey_for_method("apikey", headers), do: MCP.Auth.get_apikey(headers)
  defp apikey_for_method(_, _headers), do: nil

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
