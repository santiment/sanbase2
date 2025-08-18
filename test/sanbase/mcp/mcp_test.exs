defmodule SanbaseWeb.Graphql.MCPTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2]

  setup do
    user = insert(:user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    %{user: user, apikey: apikey}
  end

  test "authentication", context do
    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Apikey #{context.apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    # The MCP client sends a request to fetch the server capabilities.
    # After the server response is processed, Hermes calls
    # Hermes.Client.State.update_server_info/3 to set the server capabilities.
    # The sleep is here so we wait for the response, otherwise the call_tool/2
    # is called while `server_capabilities` are `nil` and we get the error
    # `Server capabilities not set`

    assert %{"tools" => _} = Sanbase.MCP.Server.server_capabilities()
    assert client |> Process.alive?() == true
    assert Sanbase.MCP.Client |> Process.whereis() |> Process.alive?() == true
    assert Hermes.Server.Registry |> Process.whereis() |> Process.alive?() == true

    # It is not guaranteed that the client has received the server capabiliteies
    # so quick after starting. When the client starts it sends a request to the server
    # and if we try to call some tool before the server responds, we get an error.
    # To mitigate that try a few times to call the server, with sleep between calls.
    result =
      try_few_times(fn -> Sanbase.MCP.Client.call_tool("check_authentication", %{}) end,
        attempts: 3,
        sleep: 250
      )

    assert {:ok,
            %Hermes.MCP.Response{
              result: %{
                "content" => [
                  %{
                    "text" => json,
                    "type" => "text"
                  }
                ],
                "isError" => false
              },
              id: "req_" <> _,
              method: "tools/call",
              is_error: false
            }} = result

    assert {:ok, %{"id" => id, "email" => email, "apikey" => apikey}} = Jason.decode(json)
    assert id == context.user.id
    assert email == context.user.email
    # Assert that most of the apikey is hidden so it does not leak
    assert apikey =~ "************"
  end
end
