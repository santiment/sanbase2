defmodule SanbaseWeb.Graphql.MCPFetchMetricTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2]

  setup do
    user = insert(:user, username: "santiment_user")
    {:ok, apikey} = Sanbase.Accounts.Apikey.generate_apikey(user)

    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, _client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Apikey #{apikey}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    p1 =
      insert(:project,
        ticker: "BTC",
        slug: "bitcoin",
        name: "Bitcoin"
      )

    p2 =
      insert(:project,
        ticker: "ETH",
        slug: "ethereum",
        name: "Ethereum"
      )

    %{user: user, apikey: apikey, p1: p1, p2: p2}
  end

  test "assets and metrics discovery tool", _context do
    result =
      try_few_times(
        fn -> Sanbase.MCP.Client.call_tool("metrics_and_assets_discovery_tool", %{}) end,
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

    assert {:ok, result} = Jason.decode(json)

    assert %{
             "insights" => [
               %{
                 "title" => "Title1",
                 "author" => "santiment_user",
                 "id" => _,
                 "link" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1"]
               },
               %{
                 "title" => "Title2",
                 "author" => "santiment_user",
                 "id" => _,
                 "link" => _,
                 "prediction" => "unspecified",
                 "published_at" => _,
                 "tags" => ["TAG1", "TAG2"]
               }
             ],
             "period_end" => _,
             "period_start" => _,
             "time_period" => "7d",
             "total_count" => 2
           } = result
  end
end
