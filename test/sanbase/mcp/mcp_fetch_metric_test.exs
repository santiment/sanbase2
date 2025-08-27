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
        name: "Bitcoin",
        description: "Bitcoin Description"
      )

    p2 =
      insert(:project,
        ticker: "ETH",
        slug: "ethereum",
        name: "Ethereum",
        description: "Ethereum Description"
      )

    %{user: user, apikey: apikey, p1: p1, p2: p2}
  end

  test "assets and metrics discovery tool - available metrics for slug", _context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.available_metrics_for_selector/1,
      {:ok, ["price_usd", "daily_active_addresses"]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("metrics_and_assets_discovery_tool", %{slug: "bitcoin"})
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

      assert Jason.decode!(json_text) ==
               %{
                 "description" => "All metrics available for bitcoin",
                 "metrics" => ["daily_active_addresses", "price_usd"],
                 "metrics_count" => 2,
                 "slug" => "bitcoin"
               }
    end)
  end

  test "assets and metrics discovery tool - available slugs for metric", _context do
    Sanbase.Mock.prepare_mock2(&Sanbase.Metric.available_slugs/1, {:ok, ["bitcoin", "ethereum"]})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("metrics_and_assets_discovery_tool", %{
              metric: "daily_active_addresses"
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
               "assets" => [
                 %{
                   "description" => "Bitcoin Description",
                   "name" => "Bitcoin",
                   "slug" => "bitcoin",
                   "ticker" => "BTC"
                 },
                 %{
                   "description" => "Ethereum Description",
                   "name" => "Ethereum",
                   "slug" => "ethereum",
                   "ticker" => "ETH"
                 }
               ],
               "assets_count" => 2,
               "description" => "All slugs available for daily_active_addresses metric",
               "metric" => "daily_active_addresses"
             }
    end)
  end

  test "assets and metrics discovery tool - full list", _context do
    # No need to mock as the assets are fetched from the DB
    # and the metric list is hardcoded. No checks for available metrics per asset are made,
    # or vice versa
    result =
      try_few_times(
        fn -> Sanbase.MCP.Client.call_tool("metrics_and_assets_discovery_tool", %{}) end,
        attempts: 3,
        sleep: 250
      )

    assert {:ok,
            %Anubis.MCP.Response{
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
                 "description" => "Bitcoin Description",
                 "name" => "Bitcoin",
                 "slug" => "bitcoin",
                 "ticker" => "BTC"
               },
               %{
                 "description" => "Ethereum Description",
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
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/price"}
                 ],
                 "name" => "price_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Total market capitalization in USD",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/marketcap"}
                 ],
                 "name" => "marketcap_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Trading volume in USD",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/trading-volume"}
                 ],
                 "name" => "volume_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "Asset price denominated in BTC",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/price"}
                 ],
                 "name" => "price_btc",
                 "unit" => "BTC"
               },
               %{
                 "description" => "Realized price volatility over 1 day",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/price-volatility"}
                 ],
                 "name" => "price_volatility_1d",
                 "unit" => "percent"
               },
               %{
                 "description" => "Fully diluted valuation in USD",
                 "documentation_urls" => [
                   %{
                     "url" => "https://academy.santiment.net/metrics/fully-diluted-valuation"
                   }
                 ],
                 "name" => "fully_diluted_valuation_usd",
                 "unit" => "USD"
               },
               %{
                 "description" =>
                   "Development activity events on tracked repositories (commits, PRs, issues, etc.)",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/development-activity/development-activity"
                   }
                 ],
                 "name" => "dev_activity",
                 "unit" => "count"
               },
               %{
                 "description" =>
                   "Number of unique developers contributing across tracked repositories",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/development-activity/development-activity-contributors-count"
                   }
                 ],
                 "name" => "dev_activity_contributors_count",
                 "unit" => "count"
               },
               %{
                 "description" => "GitHub activity events for the project",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/development-activity/github-activity"
                   }
                 ],
                 "name" => "github_activity",
                 "unit" => "count"
               },
               %{
                 "description" => "Unique GitHub contributors count",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/development-activity/github-activity-contributors-count"
                   }
                 ],
                 "name" => "github_activity_contributors_count",
                 "unit" => "count"
               },
               %{
                 "description" => "Total social media mentions and discussions",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/social-volume"}
                 ],
                 "name" => "social_volume_total",
                 "unit" => "count"
               },
               %{
                 "description" => "Share of total crypto social mentions attributed to the asset",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/social-dominance"}
                 ],
                 "name" => "social_dominance_total",
                 "unit" => "percent"
               },
               %{
                 "description" => "Overall weighted social sentiment score",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/sentiment-metrics/weighted-sentiment-metrics"
                   }
                 ],
                 "name" => "sentiment_weighted_total",
                 "unit" => "score"
               },
               %{
                 "description" =>
                   "Number of followers on the project's official Twitter/X account",
                 "documentation_urls" => [],
                 "name" => "twitter_followers",
                 "unit" => "count"
               },
               %{
                 "description" => "Daily active addresses",
                 "documentation_urls" => [
                   %{
                     "url" => "https://academy.santiment.net/metrics/daily-active-addresses"
                   }
                 ],
                 "name" => "daily_active_addresses",
                 "unit" => "count"
               },
               %{
                 "description" => "Number of on-chain transactions",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/transaction-count"}
                 ],
                 "name" => "transactions_count",
                 "unit" => "count"
               },
               %{
                 "description" => "On-chain transaction volume in number of coins/tokens",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/transaction-volume"}
                 ],
                 "name" => "transaction_volume",
                 "unit" => "count"
               },
               %{
                 "description" => "On-chain transaction volume in USD",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/transaction-volume"}
                 ],
                 "name" => "transaction_volume_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "New addresses that made their first on-chain transaction",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/network-growth"}
                 ],
                 "name" => "network_growth",
                 "unit" => "count"
               },
               %{
                 "description" => "Market Value to Realized Value ratio (USD terms)",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/mvrv"}
                 ],
                 "name" => "mvrv_usd",
                 "unit" => "ratio"
               },
               %{
                 "description" => "Amount of tokens held on exchange addresses",
                 "documentation_urls" => [
                   %{
                     "url" =>
                       "https://academy.santiment.net/metrics/supply-on-or-outside-exchanges"
                   }
                 ],
                 "name" => "supply_on_exchanges",
                 "unit" => "tokens"
               },
               %{
                 "description" => "USD value of tokens deposited to exchange addresses",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/exchange-funds-flow"}
                 ],
                 "name" => "exchange_inflow_usd",
                 "unit" => "USD"
               },
               %{
                 "description" => "USD value of tokens withdrawn from exchange addresses",
                 "documentation_urls" => [
                   %{"url" => "https://academy.santiment.net/metrics/exchange-funds-flow"}
                 ],
                 "name" => "exchange_outflow_usd",
                 "unit" => "USD"
               }
             ],
             "metrics_count" => 23
           } =
             result

    result |> dbg()
  end

  test "fetch metric with wrong asset name" do
    result =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("fetch_metric_data_tool", %{
            slug: "not_supported_slug",
            metric: "price_usd"
          })
        end,
        attempts: 3,
        sleep: 250
      )

    assert {
             :ok,
             %Anubis.MCP.Response{
               id: _,
               is_error: true,
               method: "tools/call",
               result: %{
                 "content" => [
                   %{
                     "text" => "Slug 'not_supported_slug' mistyped or not supported.",
                     "type" => "text"
                   }
                 ],
                 "isError" => true
               }
             }
           } = result
  end

  test "fetch metric with wrong metric name", context do
    result =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("fetch_metric_data_tool", %{
            slug: context.p1.slug,
            metric: "not_supported_metric"
          })
        end,
        attempts: 3,
        sleep: 250
      )

    assert {
             :ok,
             %Anubis.MCP.Response{
               id: _,
               is_error: true,
               method: "tools/call",
               result: %{
                 "content" => [
                   %{
                     "text" => "Metric 'not_supported_metric' mistyped or not supported.",
                     "type" => "text"
                   }
                 ],
                 "isError" => true
               }
             }
           } = result
  end

  test "fetch metric - success", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.timeseries_data/5,
      {:ok,
       [
         %{datetime: ~U[2020-01-01 00:00:00Z], value: 1.5},
         %{datetime: ~U[2020-01-02 00:00:00Z], value: 2.2},
         %{datetime: ~U[2020-01-03 00:00:00Z], value: 2.8},
         %{datetime: ~U[2020-01-04 00:00:00Z], value: 5.8}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("fetch_metric_data_tool", %{
              slug: context.p1.slug,
              metric: "daily_active_addresses"
            })
          end,
          attempts: 3,
          sleep: 250
        )

      assert {:ok,
              %Anubis.MCP.Response{
                id: _,
                is_error: false,
                method: "tools/call",
                result: %{
                  "content" => [
                    %{
                      "text" => json_text,
                      "type" => "text"
                    }
                  ],
                  "isError" => false
                }
              }} = result

      assert %{
               "data" => [
                 %{"datetime" => "2020-01-01T00:00:00Z", "value" => 1.5},
                 %{"datetime" => "2020-01-02T00:00:00Z", "value" => 2.2},
                 %{"datetime" => "2020-01-03T00:00:00Z", "value" => 2.8},
                 %{"datetime" => "2020-01-04T00:00:00Z", "value" => 5.8}
               ],
               "data_points" => 4,
               "interval" => "1d",
               "metric" => "daily_active_addresses",
               "period" => "last_30_days",
               "slug" => "bitcoin"
             } == Jason.decode!(json_text)
    end)
  end
end
