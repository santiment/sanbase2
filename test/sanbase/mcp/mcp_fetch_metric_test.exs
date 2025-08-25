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
             "assets" => [
               %{
                 "description" => nil,
                 "name" => "Bitcoin",
                 "slug" => "bitcoin",
                 "ticker" => "BTC"
               },
               %{
                 "description" => nil,
                 "name" => "Ethereum",
                 "slug" => "ethereum",
                 "ticker" => "ETH"
               }
             ],
             "assets_count" => 2,
             "description" => "All available metrics and slugs",
             "metrics" => [
               %{
                 "description" => "Price in USD for cryptocurrencies",
                 "name" => "price_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Total market capitalization in USD",
                 "name" => "marketcap_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Trading volume in USD",
                 "name" => "volume_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Asset price denominated in BTC",
                 "name" => "price_btc",
                 "unit" => "BTC"
               },
               %{
                 "description" => "Realized price volatility over 1 day",
                 "name" => "price_volatility_1d",
                 "unit" => "percent"
               },
               %{
                 "description" => "Fully diluted valuation in USD",
                 "name" => "fully_diluted_valuation_usd",
                 "unit" => "USD"
               },
               %{
                 "description" =>
                   "Development activity events on tracked repositories (commits, PRs, issues, etc.)",
                 "name" => "dev_activity",
                 "unit" => "count"
               },
               %{
                 "description" =>
                   "Number of unique developers contributing across tracked repositories",
                 "name" => "dev_activity_contributors_count",
                 "unit" => "count"
               },
               %{
                 "description" => "GitHub activity events for the project",
                 "name" => "github_activity",
                 "unit" => "count"
               },
               %{
                 "description" => "Unique GitHub contributors count",
                 "name" => "github_activity_contributors_count",
                 "unit" => "count"
               },
               %{
                 "description" => "Total social media mentions and discussions",
                 "name" => "social_volume_total",
                 "unit" => "count"
               },
               %{
                 "description" => "Share of total crypto social mentions attributed to the asset",
                 "name" => "social_dominance_total",
                 "unit" => "percent"
               },
               %{
                 "description" => "Overall weighted social sentiment score",
                 "name" => "sentiment_weighted_total",
                 "unit" => "score"
               },
               %{
                 "description" =>
                   "Number of followers on the project's official Twitter/X account",
                 "name" => "twitter_followers",
                 "unit" => "count"
               },
               %{
                 "description" => "Daily active addresses",
                 "name" => "daily_active_addresses",
                 "unit" => "count"
               },
               %{
                 "description" => "Number of on-chain transactions",
                 "name" => "transactions_count",
                 "unit" => "count"
               },
               %{
                 "description" => "On-chain transaction volume in number of coins/tokens",
                 "name" => "transaction_volume",
                 "unit" => "count"
               },
               %{
                 "description" => "On-chain transaction volume in USD",
                 "name" => "transaction_volume_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "New addresses that made their first on-chain transaction",
                 "name" => "network_growth",
                 "unit" => "count"
               },
               %{
                 "description" => "Market Value to Realized Value ratio (USD terms)",
                 "name" => "mvrv_usd",
                 "unit" => "ratio"
               },
               %{
                 "description" => "Amount of tokens held on exchange addresses",
                 "name" => "supply_on_exchanges",
                 "unit" => "tokens"
               },
               %{
                 "description" => "USD value of tokens deposited to exchange addresses",
                 "name" => "exchange_inflow_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "USD value of tokens withdrawn from exchange addresses",
                 "name" => "exchange_outflow_usd",
                 "unit" => "USD"
               }
             ],
             "metrics_count" => 23
           } = result
  end
end
