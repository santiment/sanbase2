defmodule SanbaseWeb.Graphql.MCPSocialToolsTest do
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

    insert(:project, ticker: "BTC", slug: "bitcoin", name: "Bitcoin")

    :ok
  end

  describe "fetch_metric_data_tool with text" do
    test "returns the series keyed by the search term" do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.Metric.timeseries_data/5,
        {:ok,
         [
           %{datetime: ~U[2020-01-01 00:00:00Z], value: 10},
           %{datetime: ~U[2020-01-02 00:00:00Z], value: 25}
         ]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 call_tool("fetch_metric_data_tool", %{
                   metric: "social_volume_total",
                   text: "sold"
                 })

        assert %{
                 "metric" => "social_volume_total",
                 "text" => "sold",
                 "data" => %{
                   "sold" => [
                     %{"datetime" => "2020-01-01T00:00:00Z", "value" => 10},
                     %{"datetime" => "2020-01-02T00:00:00Z", "value" => 25}
                   ]
                 }
               } = decode(response)

        refute Map.has_key?(decode(response), "slugs")
      end)
    end

    test "rejects text for a metric without a text selector" do
      assert {:ok, response} =
               call_tool("fetch_metric_data_tool", %{
                 metric: "daily_active_addresses",
                 text: "sold"
               })

      assert response.is_error
      assert error_text(response) =~ "does not support `text`"
    end

    test "rejects slugs and text together" do
      assert {:ok, response} =
               call_tool("fetch_metric_data_tool", %{
                 metric: "social_volume_total",
                 slugs: ["bitcoin"],
                 text: "sold"
               })

      assert response.is_error
      assert error_text(response) =~ "not both"
    end

    test "rejects a call with neither slugs nor text" do
      assert {:ok, response} =
               call_tool("fetch_metric_data_tool", %{metric: "social_volume_total"})

      assert response.is_error
      assert error_text(response) =~ "Provide either `slugs`"
    end
  end

  describe "combined_trends_tool" do
    test "says when older trend periods were dropped" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      stories =
        for hours_ago <- [18, 12, 6], into: %{} do
          story = %{
            title: "Story #{hours_ago}",
            summary: "Summary",
            score: 1.0,
            search_text: "query",
            related_tokens: [],
            bullish_ratio: 0.5,
            bearish_ratio: 0.5
          }

          {DateTime.add(now, -hours_ago * 3600, :second), [story]}
        end

      Sanbase.Mock.prepare_mock2(
        &Sanbase.SocialData.TrendingStories.get_trending_stories/4,
        {:ok, stories}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 call_tool("combined_trends_tool", %{
                   time_period: "2d",
                   include_words: false
                 })

        %{"metadata" => metadata, "trends" => %{"trending_stories" => periods}} =
          decode(response)

        assert length(periods) == 2

        expected_since = DateTime.add(now, -12 * 3600, :second) |> DateTime.to_iso8601()
        assert metadata["returned_since"] == expected_since
        assert metadata["notice"] =~ "Only the 2 most recent 6h trend periods"
      end)
    end

    test "rejects size above 10" do
      assert {:ok, response} = call_tool("combined_trends_tool", %{size: 30})

      assert response.is_error
    end
  end

  defp call_tool(name, args) do
    try_few_times(fn -> Sanbase.MCP.Client.call_tool(name, args) end, attempts: 3, sleep: 250)
  end

  defp decode(%Anubis.MCP.Response{result: %{"content" => [%{"text" => text}]}}),
    do: Jason.decode!(text)

  defp error_text(%Anubis.MCP.Response{result: %{"content" => [%{"text" => text} | _]}}),
    do: text
end
