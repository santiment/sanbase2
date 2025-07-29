defmodule Sanbase.MCP.Server do
  use Hermes.Server,
    name: "My Server",
    version: "1.0.0",
    capabilities: [:tools]

  require Logger

  alias Hermes.Server.Response

  @impl true
  # this callback will be called when the
  # MCP initialize lifecycle completes
  def init(client_info, frame) do
    client_info |> dbg()
    frame |> dbg()

    {:ok,
     frame
     |> assign(counter: 0)
     |> register_tool("echo",
       input_schema: %{
         text: {:required, :string, max: 150, description: "the text to be echoed"}
       },
       annotations: %{read_only: true},
       description: "echoes everything the user says to the LLM"
     )}
  end

  @impl true
  def handle_tool_call("echo", %{text: text}, frame) do
    IO.inspect("HERKHEKRHAK")
    Logger.info("This tool was called #{frame.assigns.counter + 1}")
    response = Response.tool() |> Response.text(text)
    {:reply, response, assign(frame, counter: frame.assigns.counter + 1)}
  end
end
