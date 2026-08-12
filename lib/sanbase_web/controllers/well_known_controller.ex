defmodule SanbaseWeb.WellKnownController do
  use SanbaseWeb, :controller

  @doc """
  Returns the ownership proof for the Glama MCP directory listing
  (https://glama.ai/mcp/connectors/io.github.santiment/santiment-mcp).

  Glama re-verifies this URL continuously — removing the endpoint lapses
  the claim on the listing.

  ## Example

      GET /.well-known/glama.json
      {"$schema": "https://glama.ai/mcp/schemas/connector.json",
       "maintainers": [{"email": "team@santiment.net"}]}
  """
  @spec glama(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def glama(conn, _params) do
    json(conn, %{
      "$schema" => "https://glama.ai/mcp/schemas/connector.json",
      "maintainers" => [%{"email" => "team@santiment.net"}]
    })
  end
end
