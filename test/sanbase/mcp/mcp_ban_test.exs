defmodule Sanbase.MCP.BanTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory
  import Sanbase.TestHelpers, only: [try_few_times: 2, wait_for_mcp_initialization: 0]

  alias Sanbase.Accounts.User
  alias Sanbase.MCP.ToolInvocation

  @moduletag capture_log: true

  setup do
    user = insert(:user, email: "banned_user@santiment.net")
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
               "user-agent" => "Claude-User/1.0",
               "host" => "localhost:#{port}"
             }
           ]},
        client_info: %{"name" => "BanTestClient", "version" => "1.0.0"},
        capabilities: %{"tools" => %{}},
        protocol_version: "2025-03-26"
      )

    wait_for_mcp_initialization()
    insert(:project, ticker: "BTC", slug: "bitcoin", name: "Bitcoin")

    on_exit(fn ->
      if pid = Process.whereis(Sanbase.MCP.Client) do
        try do
          GenServer.stop(pid, :normal, 1000)
        catch
          :exit, _ -> :ok
        end
      end
    end)

    %{user: user}
  end

  test "banned user gets banned error and the attempt is recorded", %{user: user} do
    User.mcp_ban!(user, "abuse")

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
    assert error_text =~ "banned"

    invocations = ToolInvocation.list_invocations([])

    banned_inv =
      Enum.find(invocations, fn i ->
        i.tool_name == "metrics_and_assets_discovery_tool" and i.error_message == "banned"
      end)

    assert banned_inv != nil
    assert banned_inv.is_successful == false
    assert banned_inv.duration_ms == 0
    assert banned_inv.user_id == user.id
    assert banned_inv.client == "claude"
    assert banned_inv.user_agent == "Claude-User/1.0"
    assert banned_inv.kind == "tool"
  end

  test "unbanned user can call tools again", %{user: user} do
    User.mcp_ban!(user, "abuse")
    {:ok, fresh} = User.by_id(user.id)
    User.mcp_unban!(fresh)

    Sanbase.Mock.prepare_mock2(
      &Sanbase.Metric.available_slugs/1,
      {:ok, ["bitcoin"]}
    )
    |> Sanbase.Mock.run_with_mocks(fn ->
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

      assert {:ok, %Anubis.MCP.Response{is_error: false}} = result
    end)
  end
end
