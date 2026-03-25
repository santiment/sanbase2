defmodule Sanbase.MCP.Client do
  @moduledoc "Thin wrapper around Anubis.Client for the Sanbase MCP test client"

  def start_link(opts) do
    opts = Keyword.put(opts, :name, __MODULE__)
    Anubis.Client.Supervisor.start_link(opts)
  end

  def call_tool(name, arguments \\ nil, opts \\ []) do
    Anubis.Client.call_tool(__MODULE__, name, arguments, opts)
  end

  def get_server_capabilities do
    Anubis.Client.get_server_capabilities(__MODULE__)
  end
end
