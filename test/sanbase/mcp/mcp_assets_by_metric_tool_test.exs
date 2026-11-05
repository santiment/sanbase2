defmodule SanbaseWeb.Graphql.MCPAssetsByMetricToolTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2, wait_for_mcp_initialization: 0]

  setup do
    user = insert(:user, username: "santiment_user")
    bearer_token = Sanbase.TestHelpers.setup_mcp_oauth_client(user)

    port = Sanbase.Utils.Config.module_get(SanbaseWeb.Endpoint, [:http, :port])

    {:ok, _client} =
      Sanbase.MCP.Client.start_link(
        transport:
          {:streamable_http,
           [
             base_url: "http://localhost:#{port}",
             headers: %{
               "authorization" => "Bearer #{bearer_token}",
               "content-type" => "application/json",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "SanbaseTestMCPClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    wait_for_mcp_initialization()

    _p = insert(:project, ticker: "BTC", slug: "bitcoin", name: "Bitcoin")
    _p = insert(:project, ticker: "ETH", slug: "ethereum", name: "Ethereum")
    _p = insert(:project, ticker: "SAN", slug: "santiment", name: "Santiment")
    _p = insert(:project, ticker: "MKR", slug: "maker", name: "Maker")
    _p = insert(:project, ticker: "SOL", slug: "solana", name: "Solana")

    %{user: user}
  end

  test "just order assets by price_usd", _context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
      {:ok, ["bitcoin", "solana", "ethereum", "maker", "santiment"]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, %{"bitcoin" => 100_000, "solana" => 200, "ethereum" => 3000, "maker" => 1500}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("assets_by_metric_tool", %{
              metric: "price_usd",
              from: "utc_now-1d",
              to: "utc_now",
              page: 1,
              page_size: 5,
              sort: "desc"
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
               "assets" => ["bitcoin", "solana", "ethereum", "maker", "santiment"],
               "values" => [
                 %{"slug" => "bitcoin", "price_usd" => 100_000},
                 %{"slug" => "solana", "price_usd" => 200},
                 %{"slug" => "ethereum", "price_usd" => 3000},
                 %{"slug" => "maker", "price_usd" => 1500},
                 %{"slug" => "santiment", "price_usd" => nil}
               ],
               "page" => 1,
               "page_size" => 5,
               "total_assets" => 5
             }
    end)
  end

  test "filter and order assets by price_usd", _context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_by_filter/6,
      {:ok, ["ethereum", "bitcoin", "solana", "maker"]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
      {:ok, ["bitcoin", "solana", "ethereum", "maker"]}
    )
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.aggregated_timeseries_data/5,
      {:ok, %{"bitcoin" => 100_000, "solana" => 200, "ethereum" => 3000}}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("assets_by_metric_tool", %{
              metric: "price_usd",
              from: "utc_now-1d",
              to: "utc_now",
              operator: "greater_than",
              threshold: 1000.0,
              page: 1,
              page_size: 3,
              sort: "desc"
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
               "values" => [
                 %{"slug" => "bitcoin", "price_usd" => 100_000},
                 %{"slug" => "solana", "price_usd" => 200},
                 %{"slug" => "ethereum", "price_usd" => 3000}
               ],
               "page" => 1,
               "page_size" => 3,
               "total_assets" => 4
             }
    end)
  end

  test "returns value_metrics as percent change next to the ranked metric", _context do
    # The first/last values of price_usd in the window give the change; the
    # ranked marketcap_usd comes with its default aggregation.
    aggregated = fn
      "marketcap_usd", _selector, _from, _to, _opts ->
        {:ok, %{"bitcoin" => 2.0e12, "ethereum" => 4.0e11, "solana" => 9.0e10}}

      "price_usd", _selector, _from, _to, opts ->
        case Keyword.get(opts, :aggregation) do
          :first -> {:ok, %{"bitcoin" => 100.0, "ethereum" => 50.0, "solana" => 0}}
          :last -> {:ok, %{"bitcoin" => 104.8, "ethereum" => 49.5, "solana" => 10.0}}
        end
    end

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
      {:ok, ["bitcoin", "ethereum", "solana"]}
    )
    |> Sanbase.Mock.prepare_mock(Sanbase.Metric, :aggregated_timeseries_data, aggregated)
    |> Sanbase.Mock.run_with_mocks(fn ->
      response =
        call_tool(%{
          metric: "marketcap_usd",
          from: "utc_now-1d",
          to: "utc_now",
          page: 1,
          page_size: 3,
          sort: "desc",
          value_metrics: ["price_usd"],
          value_aggregation: "percent_change"
        })

      assert response["values"] == [
               %{
                 "slug" => "bitcoin",
                 "marketcap_usd" => 2.0e12,
                 "price_usd_percent_change" => 4.8
               },
               %{
                 "slug" => "ethereum",
                 "marketcap_usd" => 4.0e11,
                 "price_usd_percent_change" => -1.0
               },
               # A zero start value has no percent change.
               %{"slug" => "solana", "marketcap_usd" => 9.0e10, "price_usd_percent_change" => nil}
             ]
    end)
  end

  test "extra filters narrow the ranking to assets that pass all of them", _context do
    slugs_by_filter = fn
      "price_usd", _from, _to, _operator, _threshold, _opts ->
        {:ok, ["bitcoin", "ethereum", "maker"]}

      "daily_active_addresses", _from, _to, _operator, _threshold, _opts ->
        {:ok, ["ethereum", "maker", "solana"]}
    end

    Sanbase.Mock.prepare_mock(Sanbase.Metric, :slugs_by_filter, slugs_by_filter)
    |> Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.slugs_order/5,
      {:ok, ["bitcoin", "solana", "ethereum", "maker", "santiment"]}
    )
    |> Sanbase.Mock.prepare_mock2(&Sanbase.Metric.aggregated_timeseries_data/5, {:ok, %{}})
    |> Sanbase.Mock.run_with_mocks(fn ->
      response =
        call_tool(%{
          metric: "marketcap_usd",
          from: "utc_now-7d",
          to: "utc_now",
          page: 1,
          page_size: 10,
          sort: "desc",
          filters: [
            %{metric: "price_usd", operator: "percent_down", threshold: 5},
            %{metric: "daily_active_addresses", operator: "greater_than", threshold: 1000}
          ]
        })

      assert response["assets"] == ["ethereum", "maker"]
      assert response["total_assets"] == 2
    end)
  end

  test "rejects a value metric that cannot be fetched for many assets", _context do
    {:ok, %Anubis.MCP.Response{is_error: true, result: %{"content" => [%{"text" => text}]}}} =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("assets_by_metric_tool", %{
            metric: "marketcap_usd",
            from: "utc_now-1d",
            to: "utc_now",
            page: 1,
            page_size: 10,
            sort: "desc",
            value_metrics: ["social_volume_total"]
          })
        end,
        attempts: 3,
        sleep: 250
      )

    assert text =~ "Value metric 'social_volume_total' cannot be fetched for many assets"
  end

  defp call_tool(args) do
    {:ok, %Anubis.MCP.Response{is_error: false, result: %{"content" => [%{"text" => json}]}}} =
      try_few_times(
        fn -> Sanbase.MCP.Client.call_tool("assets_by_metric_tool", args) end,
        attempts: 3,
        sleep: 250
      )

    Jason.decode!(json)
  end
end
