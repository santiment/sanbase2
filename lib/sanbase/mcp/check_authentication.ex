defmodule Sanbase.MCP.CheckAuthentication do
  @moduledoc "Return information about the authenticated user, if any"
  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Sanbase.Billing.Subscription
  alias Sanbase.MCP

  schema do
    # No arguments
  end

  @impl true
  def execute(params, frame) do
    if user = frame.assigns[:current_user] do
      response_data = %{
        id: user.id,
        email: user.email,
        subscriptions: Subscription.user_subscription_names(user),
        apikey: MCP.Auth.get_apikey(frame.transport.req_headers) |> obfuscate_apikey()
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      error = unauthorized_error_msg(frame)
      {:reply, Response.error(Response.tool(), error), frame}
    end
  end

  defp unauthorized_error_msg(frame) do
    specific_error =
      if MCP.Auth.get_header(frame.transport.req_headers, "authorization") do
        "Authorization header is present, but invalid."
      else
        "No Authorization header provided"
      end

    """
    Unauthorized.

    #{specific_error}

    The header value must be one of:
    Apikey <your api key>
    Bearer <your api key>

    Keep in mind that the MCP Inspector automatically prepends the value with Bearer
    """
  end

  defp obfuscate_apikey(nil), do: nil

  defp obfuscate_apikey(apikey) do
    String.duplicate("*", String.length(apikey))
    |> String.replace_prefix("***", String.slice(apikey, 0, 3))
    |> String.replace_suffix("***", String.slice(apikey, -3, 3))
  end
end
