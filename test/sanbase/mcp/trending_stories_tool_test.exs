defmodule SanbaseWeb.Graphql.MCPTrendingStoriesTest do
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

    # Mock trending stories data for the test
    mock_stories_data = [
      [
        DateTime.to_unix(~U[2024-01-01 12:00:00Z]),
        "Bitcoin Strategic Reserve",
        "(bitcoin OR btc OR reserve OR strategic)",
        850.5,
        ["BTC_bitcoin"],
        "Discussion about Bitcoin being adopted as strategic reserve",
        0.65,
        0.25
      ],
      [
        DateTime.to_unix(~U[2024-01-01 12:00:00Z]),
        "Ethereum Upgrade News",
        "(ethereum OR eth OR upgrade)",
        720.3,
        ["ETH_ethereum"],
        "Latest developments in Ethereum network upgrades",
        0.55,
        0.30
      ]
    ]

    %{user: user, apikey: apikey, mock_stories_data: mock_stories_data}
  end

  test "trending stories discovery with default parameters", _context do
    # The query_reduce function returns data differently - it processes each row with a reducer function
    mock_result = %{
      ~U[2024-01-01 12:00:00Z] => [
        %{
          title: "Bitcoin Strategic Reserve",
          summary: "Discussion about Bitcoin being adopted as strategic reserve",
          bearish_ratio: 0.25,
          bullish_ratio: 0.65,
          score: 850.5,
          search_text: "(bitcoin OR btc OR reserve OR strategic)",
          related_tokens: ["BTC_bitcoin"]
        },
        %{
          title: "Ethereum Upgrade News",
          summary: "Latest developments in Ethereum network upgrades",
          bearish_ratio: 0.30,
          bullish_ratio: 0.55,
          score: 720.3,
          search_text: "(ethereum OR eth OR upgrade)",
          related_tokens: ["ETH_ethereum"]
        }
      ]
    }

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query_reduce/3, {:ok, mock_result})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn -> Sanbase.MCP.Client.call_tool("trending_stories_tool", %{}) end,
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

      assert {:ok, data} = Jason.decode(json)

      assert %{
               "time_period" => "1h",
               "size" => 10,
               "trending_stories" => [
                 %{
                   "datetime" => _,
                   "top_stories" => stories
                 }
               ],
               "period_start" => _,
               "period_end" => _,
               "total_time_periods" => 1
             } = data

      assert length(stories) == 2

      first_story = hd(stories)
      assert first_story["title"] == "Bitcoin Strategic Reserve"
      assert first_story["score"] == 850.5
      assert first_story["bearish_sentiment_ratio"] == 0.25
      assert first_story["bullish_sentiment_ratio"] == 0.65
      assert first_story["query"] == "(bitcoin OR btc OR reserve OR strategic)"
      assert first_story["related_tokens"] == ["BTC_bitcoin"]
    end)
  end

  test "trending stories with custom parameters", _context do
    mock_result = %{
      ~U[2024-01-01 12:00:00Z] => [
        %{
          title: "Bitcoin Strategic Reserve",
          summary: "Discussion about Bitcoin being adopted as strategic reserve",
          bearish_ratio: 0.25,
          bullish_ratio: 0.65,
          score: 850.5,
          search_text: "(bitcoin OR btc OR reserve OR strategic)",
          related_tokens: ["BTC_bitcoin"]
        }
      ]
    }

    Sanbase.Mock.prepare_mock2(&Sanbase.ClickhouseRepo.query_reduce/3, {:ok, mock_result})
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("trending_stories_tool", %{time_period: "6h", size: 5})
          end,
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
                }
              }} = result

      assert {:ok, data} = Jason.decode(json)

      assert %{
               "time_period" => "6h",
               "size" => 5
             } = data
    end)
  end
end
