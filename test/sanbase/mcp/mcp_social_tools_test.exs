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

    test "treats an empty slugs list next to text as not passed" do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.Metric.timeseries_data/5,
        {:ok, [%{datetime: ~U[2020-01-01 00:00:00Z], value: 10}]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 call_tool("fetch_metric_data_tool", %{
                   metric: "social_volume_total",
                   slugs: [],
                   text: "sold"
                 })

        refute response.is_error
        assert %{"text" => "sold", "data" => %{"sold" => [_]}} = decode(response)
      end)
    end

    test "treats blank text next to slugs as not passed" do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.Metric.timeseries_data/5,
        {:ok, [%{datetime: ~U[2020-01-01 00:00:00Z], value: 10}]}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 call_tool("fetch_metric_data_tool", %{
                   metric: "social_volume_total",
                   slugs: ["bitcoin"],
                   text: ""
                 })

        refute response.is_error
        assert %{"slugs" => ["bitcoin"], "data" => %{"bitcoin" => [_]}} = decode(response)
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
    # Hourly snapshots over the last `hours`, each with `per_snapshot` stories.
    defp hourly_stories(now, hours, per_snapshot \\ 1) do
      for hours_ago <- 0..(hours - 1), into: %{} do
        stories =
          for rank <- 1..per_snapshot do
            %{
              title: "Story #{hours_ago}h ago ##{rank}",
              summary: "Summary",
              score: 100.0 - rank,
              search_text: "query",
              related_tokens: [],
              bullish_ratio: 0.5,
              bearish_ratio: 0.5
            }
          end

        {DateTime.add(now, -hours_ago * 3600, :second), stories}
      end
    end

    defp stories_for(time_period, stories) do
      Sanbase.Mock.prepare_mock2(
        &Sanbase.SocialData.TrendingStories.get_trending_stories/4,
        {:ok, stories}
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        assert {:ok, response} =
                 call_tool("combined_trends_tool", %{
                   time_period: time_period,
                   include_words: false
                 })

        %{"metadata" => metadata, "trends" => %{"trending_stories" => periods}} =
          decode(response)

        {metadata, periods}
      end)
    end

    defp period_hours_ago(now, %{"datetime" => datetime}) do
      {:ok, datetime, _} = DateTime.from_iso8601(datetime)
      div(DateTime.diff(now, datetime, :second), 3600)
    end

    test "a window up to a day returns the latest snapshot, which covers the day" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {metadata, periods} = stories_for("1d", hourly_stories(now, 30, 10))

      assert [period] = periods
      assert period_hours_ago(now, period) == 0
      assert length(period["top_stories"]) == 10
      assert metadata["coverage"] =~ "24 hours before its datetime"
      refute Map.has_key?(metadata, "notice")
    end

    test "a short window still finds a snapshot older than the window" do
      # Social data lags: the newest snapshot can be older than a 1h window.
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      stories =
        now |> hourly_stories(30) |> Map.reject(fn {dt, _} -> DateTime.diff(now, dt) < 7200 end)

      {_metadata, periods} = stories_for("1h", stories)
      assert [period] = periods
      assert period_hours_ago(now, period) == 2
    end

    test "a multi-day window returns one snapshot per day, a day apart" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {metadata, periods} = stories_for("3d", hourly_stories(now, 80, 10))

      assert Enum.map(periods, &period_hours_ago(now, &1)) == [48, 24, 0]
      # Three snapshots share the item budget.
      assert Enum.all?(periods, &(length(&1["top_stories"]) == 6))

      expected_since = now |> DateTime.add(-72 * 3600, :second) |> DateTime.to_iso8601()
      assert metadata["covered_since"] == expected_since
    end

    test "past a week only the last seven days are covered, and it says so" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {metadata, periods} = stories_for("10d", hourly_stories(now, 240, 10))

      assert length(periods) == 7
      assert Enum.all?(periods, &(length(&1["top_stories"]) == 3))
      assert metadata["coverage"] =~ "longer than 7 days"
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
