defmodule Sanbase.MCP.RateLimitTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.{Restrictions, ToolInvocation}

  describe "check_rate_limit/2 (global)" do
    setup do
      user = insert(:user, username: "rate_limit_user", email: "rate_limit@santiment.net")
      %{user: user}
    end

    test "returns {:ok, true} when under all limits", %{user: user} do
      assert {:ok, true} = ToolInvocation.check_rate_limit(user.id, :free)
    end

    test "returns error when minute limit is reached", %{user: user} do
      with_overrides(%{global: %{free: %{minute: 3}}}, fn ->
        insert_invocations(user.id, "fetch_metric_data_tool", 3)
        assert {:error, msg} = ToolInvocation.check_rate_limit(user.id, :free)
        assert msg =~ "per minute"
      end)
    end

    test "returns error when hour limit is reached", %{user: user} do
      with_overrides(%{global: %{free: %{hour: 3}}}, fn ->
        insert_invocations(user.id, "fetch_metric_data_tool", 3)
        assert {:error, msg} = ToolInvocation.check_rate_limit(user.id, :free)
        assert msg =~ "per hour"
      end)
    end

    test "returns error when day limit is reached", %{user: user} do
      with_overrides(%{global: %{free: %{day: 3}}}, fn ->
        insert_invocations(user.id, "fetch_metric_data_tool", 3)
        assert {:error, msg} = ToolInvocation.check_rate_limit(user.id, :free)
        assert msg =~ "per day"
      end)
    end

    test "returns error when monthly (rolling 30d) limit is reached", %{user: user} do
      with_overrides(%{global: %{free: %{month: 3}}}, fn ->
        insert_invocations(user.id, "fetch_metric_data_tool", 3)
        assert {:error, msg} = ToolInvocation.check_rate_limit(user.id, :free)
        assert msg =~ "per 30 days"
      end)
    end

    test "tier choice changes the applicable limits", %{user: user} do
      # Set Free very low, Pro very high. The same call count is over Free's
      # cap but under Pro's, proving the tier argument is honored.
      with_overrides(
        %{
          global: %{
            free: %{minute: 1},
            pro: %{minute: 100}
          }
        },
        fn ->
          insert_invocations(user.id, "fetch_metric_data_tool", 2)
          assert {:error, _} = ToolInvocation.check_rate_limit(user.id, :free)
          assert {:ok, true} = ToolInvocation.check_rate_limit(user.id, :pro)
        end
      )
    end
  end

  describe "check_tool_rate_limit/3 (per-tool)" do
    setup do
      user = insert(:user, username: "tool_limit_user", email: "tool_limit@santiment.net")
      %{user: user}
    end

    test "combined_trends_tool has its own tighter limits", %{user: user} do
      with_overrides(%{combined_trends: %{free: %{minute: 2}}}, fn ->
        insert_invocations(user.id, "combined_trends_tool", 2)

        assert {:error, msg} =
                 ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool", :free)

        assert msg =~ "combined_trends_tool"
        assert msg =~ "per minute"
      end)
    end

    test "other tools are unaffected by combined_trends limits", %{user: user} do
      with_overrides(%{combined_trends: %{free: %{minute: 2}}}, fn ->
        insert_invocations(user.id, "fetch_metric_data_tool", 5)

        assert {:ok, true} =
                 ToolInvocation.check_tool_rate_limit(user.id, "fetch_metric_data_tool", :free)
      end)
    end

    test "combined_trends invocations don't affect other-tool sub-caps", %{user: user} do
      with_overrides(%{combined_trends: %{free: %{minute: 2}}}, fn ->
        insert_invocations(user.id, "combined_trends_tool", 2)

        assert {:error, _} =
                 ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool", :free)

        assert {:ok, true} =
                 ToolInvocation.check_tool_rate_limit(user.id, "fetch_metric_data_tool", :free)
      end)
    end

    test "higher tier gets larger combined_trends quota", %{user: user} do
      with_overrides(
        %{
          combined_trends: %{
            free: %{minute: 1},
            max: %{minute: 100}
          }
        },
        fn ->
          insert_invocations(user.id, "combined_trends_tool", 2)

          assert {:error, _} =
                   ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool", :free)

          assert {:ok, true} =
                   ToolInvocation.check_tool_rate_limit(user.id, "combined_trends_tool", :max)
        end
      )
    end
  end

  describe "team_member?/1" do
    test "matches the @santiment.net domain case-insensitively" do
      assert ToolInvocation.team_member?(%{email: "alice@santiment.net"})
      assert ToolInvocation.team_member?(%{email: "Bob@Santiment.NET"})
    end

    test "matches built-in team emails" do
      assert ToolInvocation.team_member?(%{email: "tsvetozar.penov@gmail.com"})
    end

    test "matches configured team emails (case-insensitive)" do
      original = Application.get_env(:sanbase, Sanbase.MCP.ToolInvocation)

      Application.put_env(
        :sanbase,
        Sanbase.MCP.ToolInvocation,
        Keyword.merge(original || [], team_emails: "teammate@example.com")
      )

      assert ToolInvocation.team_member?(%{email: "teammate@example.com"})
      assert ToolInvocation.team_member?(%{email: "TEAMMATE@example.com"})

      Application.put_env(:sanbase, Sanbase.MCP.ToolInvocation, original)
    end

    test "returns false for unrelated emails and missing input" do
      refute ToolInvocation.team_member?(%{email: "external@example.com"})
      refute ToolInvocation.team_member?(%{email: nil})
      refute ToolInvocation.team_member?(nil)
    end
  end

  describe "Restrictions.tier_for_user/1" do
    test "returns :free for nil and users without subscriptions" do
      assert :free == Restrictions.tier_for_user(nil)
      user = insert(:user)
      assert :free == Restrictions.tier_for_user(user)
    end
  end

  defp insert_invocations(user_id, tool_name, count) do
    for _ <- 1..count do
      {:ok, _} =
        ToolInvocation.create(%{
          user_id: user_id,
          tool_name: tool_name,
          params: %{},
          is_successful: true,
          duration_ms: 100
        })
    end
  end

  # Deep-merges per-tier overrides into the configured Restrictions limits
  # for the duration of `fun`, then restores the original config.
  defp with_overrides(overrides, fun) do
    original = Application.get_env(:sanbase, Sanbase.MCP.Restrictions, [])

    merged =
      Enum.reduce(overrides, original, fn {group, tier_map}, acc ->
        existing_group = Keyword.get(acc, group, %{})

        new_group =
          Enum.reduce(tier_map, existing_group, fn {tier, fields}, group_acc ->
            Map.update(group_acc, tier, fields, &Map.merge(&1, fields))
          end)

        Keyword.put(acc, group, new_group)
      end)

    Application.put_env(:sanbase, Sanbase.MCP.Restrictions, merged)

    try do
      fun.()
    after
      Application.put_env(:sanbase, Sanbase.MCP.Restrictions, original)
    end
  end
end
