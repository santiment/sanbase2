defmodule SanbaseWeb.Graphql.ExchangeMetricsApiTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    %{user: user, apikey: apikey}
  end

  test "authentication", context do
    {:ok, client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:4000",
             headers: %{"authorization" => "Apikey #{context.apikey}"}
           ]},
        client_info: %{"name" => "MyApp", "version" => "1.0.0"},
        capabilities: %{},
        protocol_version: "2025-03-26"
      )

    assert client |> Process.alive?() == true
    assert Sanbase.MCP.Client |> Process.whereis() |> Process.alive?() == true

    assert {:ok,
            %Hermes.MCP.Response{
              result: %{
                "content" => [
                  %{
                    "text" => text,
                    "type" => "text"
                  }
                ],
                "isError" => false
              },
              id: "req_" <> _,
              method: "tools/call",
              is_error: false
            }} = Sanbase.MCP.Client.call_tool("check_authentication", %{})

    assert %{"id" => id} = Jason.decode!(text)
  end
end
