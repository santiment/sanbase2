defmodule Sanbase.MCP.RateLimitTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.ToolInvocation

  describe "check_rate_limit/1 (global)" do
    setup do
      user = insert(:user, username: "rate_limit_user", email: "rate_limit@santiment.net")
      %{user: user}
    end

    test "returns {:ok, true} when under all limits", %{user: user} do
      assert {:ok, true} = ToolInvocation.check_rate_limit(user.id)
    end

    test "returns error when minute limit is reached", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original, global_rate_limit_minute: 3)
      )

      for _ <- 1..3 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "fetch_metric_data_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      assert {:error, msg} = ToolInvocation.check_rate_limit(user.id)
      assert msg =~ "per minute"

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end

    test "returns error when hour limit is reached", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original, global_rate_limit_hour: 3, global_rate_limit_minute: 10000)
      )

      for _ <- 1..3 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "fetch_metric_data_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      assert {:error, msg} = ToolInvocation.check_rate_limit(user.id)
      assert msg =~ "per hour"

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end

    test "returns error when day limit is reached", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original,
          global_rate_limit_day: 3,
          global_rate_limit_hour: 10000,
          global_rate_limit_minute: 10000
        )
      )

      for _ <- 1..3 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "fetch_metric_data_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      assert {:error, msg} = ToolInvocation.check_rate_limit(user.id)
      assert msg =~ "per day"

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end
  end

  describe "check_tool_rate_limit/2 (per-tool)" do
    setup do
      user = insert(:user, username: "tool_limit_user", email: "tool_limit@santiment.net")
      %{user: user}
    end

    test "combined_trends_tool has its own tighter limits", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original, combined_trends_rate_limit_minute: 2)
      )

      for _ <- 1..2 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "combined_trends_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      assert {:error, msg} = ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool")
      assert msg =~ "combined_trends_tool"
      assert msg =~ "per minute"

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end

    test "other tools are unaffected by combined_trends limits", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original, combined_trends_rate_limit_minute: 2)
      )

      for _ <- 1..5 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "fetch_metric_data_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      # Other tools have no per-tool limit
      assert {:ok, true} = ToolInvocation.check_tool_rate_limit(user.id, "fetch_metric_data_tool")

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end

    test "combined_trends_tool invocations don't affect other tool limits", %{user: user} do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original, combined_trends_rate_limit_minute: 2)
      )

      # Create combined_trends invocations at the limit
      for _ <- 1..2 do
        {:ok, _} =
          ToolInvocation.create(%{
            user_id: user.id,
            tool_name: "combined_trends_tool",
            params: %{},
            is_successful: true,
            duration_ms: 100
          })
      end

      # combined_trends is rate limited
      assert {:error, _} = ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool")

      # but other tools are fine
      assert {:ok, true} = ToolInvocation.check_tool_rate_limit(user.id, "fetch_metric_data_tool")

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end
  end
end
