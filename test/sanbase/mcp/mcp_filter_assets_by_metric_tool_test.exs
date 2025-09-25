defmodule SanbaseWeb.Graphql.MCPFilterAssetsByMetricToolTest do
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

    _p = insert(:project, ticker: "BTC", slug: "bitcoin", name: "Bitcoin")
    _p = insert(:project, ticker: "ETH", slug: "ethereum", name: "Ethereum")
    _p = insert(:project, ticker: "SAN", slug: "santiment", name: "Santiment")
    _p = insert(:project, ticker: "MKR", slug: "maker", name: "Maker")
    _p = insert(:project, ticker: "SOL", slug: "solana", name: "Solana")

    %{user: user, apikey: apikey}
  end

  test "filter assets by price_usd", _context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_by_filter/6,
      {:ok, ["ethereum", "bitcoin", "solana", "maker"]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
      {:ok, ["bitcoin", "solana", "ethereum", "maker"]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("filter_assets_by_metric_tool", %{
              metric: "price_usd",
              from: "utc_now-1d",
              to: "utc_now",
              operator: "greater_than",
              threshold: 1000.0,
              page: 1,
              page_size: 3,
              sort: "asc"
            })
          end,
          attempts: 3,
          sleep: 250
        )

      assert {:ok,
              %Anubis.MCP.Response{
                result: %{
                  "content" => [
                    %{
                      "text" => json_text,
                      "type" => "text"
                    }
                  ],
                  "isError" => false
                },
                id: "req_" <> _,
                method: "tools/call",
                is_error: false
              }} = result

      assert Jason.decode!(json_text) == %{
               "assets" => ["bitcoin", "solana", "ethereum"],
               "page" => 1,
               "page_size" => 3,
               "total_assets" => 4
             }
    end)
  end
end
