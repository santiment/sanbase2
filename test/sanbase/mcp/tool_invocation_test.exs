defmodule Sanbase.MCP.ToolInvocationTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2, wait_for_mcp_initialization: 0]

  alias Sanbase.MCP.ToolInvocation

  setup do
    user = insert(:user, username: "mcp_tracking_user", email: "mcp_tracking@santiment.net")
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
        client_info: %{"name" => "TrackingTestClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    wait_for_mcp_initialization()

    insert(:project, ticker: "BTC", slug: "bitcoin", name: "Bitcoin")

    %{user: user}
  end

  test "successful tool call creates an invocation record with metrics and slugs", context do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.timeseries_data/5,
      {:ok,
       [
         %{datetime: ~U[2020-01-01 00:00:00Z], value: 1.5},
         %{datetime: ~U[2020-01-02 00:00:00Z], value: 2.2}
       ]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
      result =
        try_few_times(
          fn ->
            Sanbase.MCP.Client.call_tool("fetch_metric_data_tool", %{
              slugs: ["bitcoin"],
              metric: "price_usd"
            })
          end,
          attempts: 3,
          sleep: 250
        )

      assert {:ok, %Anubis.MCP.Response{is_error: false}} = result

      # Give the async task time to insert
      Process.sleep(500)

      invocations = ToolInvocation.list_invocations([])
      assert length(invocations) >= 1

      inv = Enum.find(invocations, &(&1.tool_name == "fetch_metric_data_tool"))
      assert inv != nil
      assert inv.is_successful == true
      assert inv.user_id == context.user.id
      assert inv.duration_ms >= 0
      assert inv.response_size_bytes > 0
      assert inv.auth_method == "oauth"
      assert inv.metrics == ["price_usd"]
      assert inv.slugs == ["bitcoin"]
      assert inv.params["metric"] == "price_usd"
      assert inv.params["slugs"] == ["bitcoin"]
    end)
  end

  test "failed tool call records error information" do
    result =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("fetch_metric_data_tool", %{
            slugs: ["nonexistent_slug"],
            metric: "price_usd"
          })
        end,
        attempts: 3,
        sleep: 250
      )

    assert {:ok, %Anubis.MCP.Response{is_error: true}} = result

    Process.sleep(500)

    invocations = ToolInvocation.list_invocations([])

    inv =
      Enum.find(invocations, fn i ->
        i.tool_name == "fetch_metric_data_tool" && i.is_successful == false
      end)

    assert inv != nil
    assert inv.is_successful == false
    assert inv.error_message != nil
    assert inv.duration_ms >= 0
  end

  test "discovery tool call extracts metrics correctly" do
    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.available_slugs/1,
      {:ok, ["bitcoin"]}
    )
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

      assert {:ok, %Anubis.MCP.Response{is_error: false}} = result

      Process.sleep(500)

      invocations = ToolInvocation.list_invocations([])

      inv = Enum.find(invocations, &(&1.tool_name == "metrics_and_assets_discovery_tool"))
      assert inv != nil
      assert inv.is_successful == true
      assert inv.metrics == ["daily_active_addresses"]
    end)
  end

  test "returns rate limit error when global limit is exceeded", context do
    original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

    Application.put_env(
      :sanbase,
      Sanbase.MCP.ToolInvocation,
      Keyword.merge(original, global_rate_limit_minute: 2)
    )

    # Pre-insert invocations to reach the limit
    for _ <- 1..2 do
      {:ok, _} =
        ToolInvocation.create(%{
          user_id: context.user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 100
        })
    end

    # This call should hit the rate limit
    result =
      try_few_times(
        fn ->
          Sanbase.MCP.Client.call_tool("metrics_and_assets_discovery_tool", %{
            metric: "price_usd"
          })
        end,
        attempts: 3,
        sleep: 250
      )

    assert {:ok, %Anubis.MCP.Response{is_error: true} = response} = result
    error_text = get_in(response.result, ["content", Access.at(0), "text"])
    assert error_text =~ "Rate limit exceeded"

    # Give the async tracking task time to insert
    Process.sleep(500)

    # Verify the rate-limited call was tracked
    invocations = ToolInvocation.list_invocations([])

    rate_limited_inv =
      Enum.find(invocations, fn i ->
        i.tool_name == "metrics_and_assets_discovery_tool" && i.is_successful == false
      end)

    assert rate_limited_inv != nil
    assert rate_limited_inv.error_message =~ "Rate limit exceeded"
    assert rate_limited_inv.duration_ms == 0

    Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
  end

  test "filters work correctly", context do
    # Insert test records directly
    {:ok, _} =
      ToolInvocation.create(%{
        user_id: context.user.id,
        tool_name: "fetch_metric_data_tool",
        params: %{"metric" => "price_usd", "slugs" => ["bitcoin"]},
        is_successful: true,
        duration_ms: 100,
        response_size_bytes: 500
      })

    {:ok, _} =
      ToolInvocation.create(%{
        tool_name: "metrics_and_assets_discovery_tool",
        params: %{"metric" => "daily_active_addresses"},
        is_successful: true,
        duration_ms: 50,
        response_size_bytes: 200
      })

    # Filter by tool name
    assert ToolInvocation.count_invocations(tool_name: "fetch_metric_data_tool") == 1
    assert ToolInvocation.count_invocations(tool_name: "metrics_and_assets_discovery_tool") == 1

    # Filter by email
    results = ToolInvocation.list_invocations(email_search: "mcp_tracking")
    assert length(results) == 1
    assert hd(results).tool_name == "fetch_metric_data_tool"

    # Filter by metric
    results = ToolInvocation.list_invocations(metric: "price_usd")
    assert length(results) == 1
    assert hd(results).tool_name == "fetch_metric_data_tool"

    results = ToolInvocation.list_invocations(metric: "daily_active_addresses")
    assert length(results) == 1
    assert hd(results).tool_name == "metrics_and_assets_discovery_tool"

    # Stats
    stats = ToolInvocation.stats_since(DateTime.add(DateTime.utc_now(), -3600, :second))
    assert stats["fetch_metric_data_tool"] == 1
    assert stats["metrics_and_assets_discovery_tool"] == 1

    # Tool names
    names = ToolInvocation.tool_names()
    assert "fetch_metric_data_tool" in names
    assert "metrics_and_assets_discovery_tool" in names
  end
end
