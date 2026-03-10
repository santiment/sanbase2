defmodule Sanbase.MCP.DevServer do
  @moduledoc "MCP dev server exposing search docs tool"

  use Anubis.Server,
    name: "sanbase-mcp-dev",
    version: "1.0.0",
    capabilities: [:tools]

  @impl true
  def init(_client_info, %Anubis.Server.Frame{} = frame) do
    user = Sanbase.MCP.Auth.headers_list_to_user(frame.context.headers)
    frame = if user, do: assign(frame, :current_user, user), else: frame
    {:ok, frame |> assign(:is_authenticated, not is_nil(user))}
  end

  @impl true
  def handle_request(request, %Anubis.Server.Frame{} = frame) do
    frame = assign_current_user(frame)
    Anubis.Server.Handlers.handle(request, __MODULE__, frame)
  end

  # Expose only the search docs tool
  component(Sanbase.MCP.SearchDocsTool)

  defp assign_current_user(%Anubis.Server.Frame{} = frame) do
    headers = frame.context.headers || %{}

    user =
      frame.assigns[:current_user] ||
        Sanbase.MCP.Auth.headers_list_to_user(headers)

    frame =
      if user do
        assign(frame, :current_user, user)
      else
        frame
      end

    assign(frame, :is_authenticated, not is_nil(user))
  end
end
