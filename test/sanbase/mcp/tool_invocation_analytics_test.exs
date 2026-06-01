defmodule Sanbase.MCP.ToolInvocationAnalyticsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.ToolInvocation
  alias Sanbase.Repo

  describe "derive_client/2 (User-Agent-only paths)" do
    test "nil input returns nil" do
      assert ToolInvocation.derive_client(nil, nil) == nil
    end

    test "matches Claude" do
      assert ToolInvocation.derive_client("Claude-User/1.0 (+https://claude.ai)", nil) ==
               "claude"
    end

    test "matches ChatGPT" do
      assert ToolInvocation.derive_client("ChatGPT-User/1.0", nil) == "chatgpt"
      assert ToolInvocation.derive_client("OpenAI/1.2.3", nil) == "chatgpt"
    end

    test "matches openai / chatgpt regardless of case and embedded substrings" do
      assert ToolInvocation.derive_client("openai", nil) == "chatgpt"
      assert ToolInvocation.derive_client("OPENAI", nil) == "chatgpt"
      assert ToolInvocation.derive_client("openai-mcp/0.1", nil) == "chatgpt"
      assert ToolInvocation.derive_client("chatgpt", nil) == "chatgpt"
    end

    test "matches Cursor" do
      assert ToolInvocation.derive_client("Cursor/0.42 mcp", nil) == "cursor"
    end

    test "unknown UA falls back to raw UA string" do
      assert ToolInvocation.derive_client("curl/8.4.0", nil) == "curl/8.4.0"
    end

    test "raw UA fallback is truncated to the column size" do
      long = String.duplicate("a", 64)
      assert ToolInvocation.derive_client(long, nil) == String.duplicate("a", 32)
    end
  end

  describe "derive_client/2" do
    test "returns nil when both inputs are absent" do
      assert ToolInvocation.derive_client(nil, nil) == nil
      assert ToolInvocation.derive_client(nil, %{}) == nil
    end

    test "matches known client from User-Agent first" do
      assert ToolInvocation.derive_client("Claude-User/1.0", nil) == "claude"
    end

    test "falls back to clientInfo.name when UA is missing" do
      assert ToolInvocation.derive_client(nil, %{"name" => "claude-ai", "version" => "0.1"}) ==
               "claude"

      assert ToolInvocation.derive_client(nil, %{"name" => "ChatGPT"}) == "chatgpt"
      assert ToolInvocation.derive_client(nil, %{"name" => "openai"}) == "chatgpt"
      assert ToolInvocation.derive_client(nil, %{"name" => "cursor-mcp"}) == "cursor"
    end

    test "uses clientInfo when UA is present but unknown" do
      assert ToolInvocation.derive_client("custom-cli/1.0", %{"name" => "Claude Desktop"}) ==
               "claude"
    end

    test "returns raw clientInfo.name when no known client matches" do
      assert ToolInvocation.derive_client(nil, %{"name" => "some-custom-client"}) ==
               "some-custom-client"
    end

    test "falls back to raw UA when clientInfo is absent and UA is unknown" do
      assert ToolInvocation.derive_client("curl/8.4.0", nil) == "curl/8.4.0"
    end

    test "prefers clientInfo.name over raw UA in the fallback" do
      assert ToolInvocation.derive_client("curl/8.4.0", %{"name" => "my-mcp-app"}) == "my-mcp-app"
    end
  end

  describe "user_agent_from_client_info/1" do
    test "returns nil for nil or empty input" do
      assert ToolInvocation.user_agent_from_client_info(nil) == nil
      assert ToolInvocation.user_agent_from_client_info(%{}) == nil
      assert ToolInvocation.user_agent_from_client_info(%{"version" => "1.0"}) == nil
    end

    test "formats name/version when both present" do
      assert ToolInvocation.user_agent_from_client_info(%{"name" => "Claude", "version" => "1.2"}) ==
               "Claude/1.2"
    end

    test "returns just name when version is missing" do
      assert ToolInvocation.user_agent_from_client_info(%{"name" => "Claude"}) == "Claude"
    end
  end

  describe "create/1 stores new fields" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "user_agent is truncated, client derived from it, kind defaults to tool", %{user: user} do
      long_ua = String.duplicate("a", 1024)

      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 10,
          user_agent: long_ua,
          client: ToolInvocation.derive_client("Claude-User/1.0", nil),
          session_id: "session-abc"
        })

      assert byte_size(inv.user_agent) == 512
      assert inv.client == "claude"
      assert inv.session_id == "session-abc"
      assert inv.kind == "tool"
    end

    test "kind prompt is accepted", %{user: user} do
      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "market_analysis_prompt",
          params: %{"slug" => "bitcoin"},
          is_successful: true,
          duration_ms: 5,
          kind: "prompt"
        })

      assert inv.kind == "prompt"
      assert inv.slugs == ["bitcoin"]
    end

    test "client column accepts arbitrary strings and is truncated", %{user: user} do
      long_client = String.duplicate("x", 64)

      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 10,
          client: long_client
        })

      assert byte_size(inv.client) == 32
    end
  end

  describe "time_series/1" do
    setup do
      user_a = insert(:user, email: "ts_a@example.com")
      user_b = insert(:user, email: "ts_b@example.com")
      %{user_a: user_a, user_b: user_b}
    end

    test "buckets by day and counts distinct users", %{user_a: user_a, user_b: user_b} do
      now = DateTime.utc_now()
      yesterday = DateTime.add(now, -24 * 3600, :second)

      seed_invocation(user_a, now)
      seed_invocation(user_a, now)
      seed_invocation(user_b, now)
      seed_invocation(user_a, DateTime.add(yesterday, -1, :second))

      since = DateTime.add(now, -7 * 24 * 3600, :second)
      rows = ToolInvocation.time_series(since: since, bucket: "day")

      assert is_list(rows)
      assert length(rows) >= 2

      total_count = rows |> Enum.map(fn {_, total, _} -> total end) |> Enum.sum()
      max_unique = rows |> Enum.map(fn {_, _, uniq} -> uniq end) |> Enum.max()

      assert total_count >= 4
      assert max_unique == 2
    end
  end

  describe "rate_limited_users/1" do
    setup do
      user = insert(:user, email: "spammer@example.com")
      %{user: user}
    end

    test "returns only users with rate-limit rejections", %{user: user} do
      {:ok, _} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: false,
          duration_ms: 0,
          error_message: "Rate limit exceeded: 25/25 MCP tool calls per minute. Please wait."
        })

      {:ok, _} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: false,
          duration_ms: 0,
          error_message: "Rate limit exceeded: hour"
        })

      {:ok, _} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: false,
          duration_ms: 0,
          error_message: "Some other failure"
        })

      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      rows = ToolInvocation.rate_limited_users(since: since)

      assert [%{user_id: id, email: "spammer@example.com", hits: 2, is_mcp_banned: false}] = rows
      assert id == user.id
    end

    test "respects min_hits", %{user: user} do
      {:ok, _} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: false,
          duration_ms: 0,
          error_message: "Rate limit exceeded: 25/25 MCP tool calls per minute. Please wait."
        })

      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      assert ToolInvocation.rate_limited_users(since: since, min_hits: 2) == []
      assert [_] = ToolInvocation.rate_limited_users(since: since, min_hits: 1)
    end
  end

  describe "list_invocations/1 with exclude_team_members" do
    setup do
      santiment_user = insert(:user, email: "alice@santiment.net")
      gmail_team_user = insert(:user, email: "alice.personal@gmail.com")
      external_user = insert(:user, email: "trader@example.com")

      {:ok, _} = create_basic_invocation(santiment_user)
      {:ok, _} = create_basic_invocation(gmail_team_user)
      {:ok, _} = create_basic_invocation(external_user)
      {:ok, anon} = create_basic_invocation(nil)

      %{
        santiment_user: santiment_user,
        gmail_team_user: gmail_team_user,
        external_user: external_user,
        anon_id: anon.id
      }
    end

    test "default behavior includes everyone", %{santiment_user: s, external_user: e} do
      emails =
        ToolInvocation.list_invocations([])
        |> Enum.map(& &1.user)
        |> Enum.map(fn
          nil -> nil
          u -> u.email
        end)

      assert s.email in emails
      assert e.email in emails
      assert nil in emails
    end

    test "exclude_team_members hides @santiment.net but keeps anonymous and externals",
         %{santiment_user: s, external_user: e, gmail_team_user: g} do
      emails =
        ToolInvocation.list_invocations(exclude_team_members: true)
        |> Enum.map(fn
          %{user: nil} -> nil
          %{user: u} -> u.email
        end)

      refute s.email in emails
      assert e.email in emails
      # gmail user is not in MCP_TEAM_EMAILS list — still visible
      assert g.email in emails
      assert nil in emails
    end

    test "exclude_team_members also hides emails from the team_emails config",
         %{gmail_team_user: g, external_user: e} do
      previous = Application.get_env(:sanbase, ToolInvocation, [])

      Application.put_env(
        :sanbase,
        ToolInvocation,
        Keyword.put(previous, :team_emails, "alice.personal@gmail.com, other@example.org")
      )

      on_exit(fn -> Application.put_env(:sanbase, ToolInvocation, previous) end)

      emails =
        ToolInvocation.list_invocations(exclude_team_members: true)
        |> Enum.map(fn
          %{user: nil} -> nil
          %{user: u} -> u.email
        end)

      refute g.email in emails
      assert e.email in emails
    end

    test "team-emails CSV is case-insensitive and trims whitespace",
         %{gmail_team_user: g} do
      previous = Application.get_env(:sanbase, ToolInvocation, [])

      Application.put_env(
        :sanbase,
        ToolInvocation,
        Keyword.put(previous, :team_emails, "  ALICE.Personal@Gmail.com  ")
      )

      on_exit(fn -> Application.put_env(:sanbase, ToolInvocation, previous) end)

      emails =
        ToolInvocation.list_invocations(exclude_team_members: true)
        |> Enum.map(fn
          %{user: nil} -> nil
          %{user: u} -> u.email
        end)

      refute g.email in emails
    end

    test "count_invocations honors exclude_team_members" do
      total = ToolInvocation.count_invocations([])
      filtered = ToolInvocation.count_invocations(exclude_team_members: true)
      assert filtered == total - 1
    end
  end

  describe "plan_snapshot_for/1" do
    test "anonymous user returns nil/nil" do
      assert ToolInvocation.plan_snapshot_for(nil) == %{product_code: nil, plan_name: nil}
    end

    test "user with no subscription buckets under FREE" do
      user = insert(:user)

      assert ToolInvocation.plan_snapshot_for(user.id) ==
               %{product_code: nil, plan_name: "FREE"}
    end

    test "user with a SANBASE PRO subscription returns SANBASE/PRO", context do
      user = insert(:user)
      plan = context.plans.plan_pro_sanbase
      insert(:subscription_pro_sanbase, user: user, plan: plan)

      assert ToolInvocation.plan_snapshot_for(user.id) ==
               %{product_code: "SANBASE", plan_name: "PRO"}
    end

    test "user with a SANAPI PRO subscription returns SANAPI/PRO", context do
      user = insert(:user)
      plan = context.plans.plan_pro
      insert(:subscription_pro, user: user, plan: plan)

      assert ToolInvocation.plan_snapshot_for(user.id) ==
               %{product_code: "SANAPI", plan_name: "PRO"}
    end
  end

  describe "create/1 snapshots plan" do
    test "stores product_code + plan_name from user's latest subscription", context do
      user = insert(:user)
      plan = context.plans.plan_pro_sanbase
      insert(:subscription_pro_sanbase, user: user, plan: plan)

      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 5
        })

      assert inv.product_code == "SANBASE"
      assert inv.plan_name == "PRO"
    end

    test "stores FREE when user has no subscription" do
      user = insert(:user)

      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 5
        })

      assert inv.plan_name == "FREE"
      assert inv.product_code == nil
    end

    test "explicit plan_name in attrs is not overwritten" do
      user = insert(:user)

      {:ok, inv} =
        ToolInvocation.create(%{
          user_id: user.id,
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 5,
          product_code: "SANAPI",
          plan_name: "BUSINESS_MAX"
        })

      assert inv.plan_name == "BUSINESS_MAX"
      assert inv.product_code == "SANAPI"
    end

    test "anonymous invocations leave plan_name nil" do
      {:ok, inv} =
        ToolInvocation.create(%{
          tool_name: "fetch_metric_data_tool",
          params: %{},
          is_successful: true,
          duration_ms: 5
        })

      assert inv.plan_name == nil
      assert inv.product_code == nil
    end
  end

  describe "plan filters and breakdowns" do
    setup do
      user_free = insert(:user, email: "free@example.com")
      user_pro = insert(:user, email: "pro@example.com")

      {:ok, _} = create_invocation_with_plan(user_free, "FREE", nil)
      {:ok, _} = create_invocation_with_plan(user_pro, "PRO", "SANBASE")
      {:ok, _} = create_invocation_with_plan(user_pro, "PRO", "SANBASE")
      {:ok, _} = create_invocation_with_plan(user_pro, "MAX", "SANBASE")

      %{user_free: user_free, user_pro: user_pro}
    end

    test "list_invocations filters by plan_name" do
      assert ToolInvocation.count_invocations(plan_name: "PRO") == 2
      assert ToolInvocation.count_invocations(plan_name: "FREE") == 1
      assert ToolInvocation.count_invocations(plan_name: "MAX") == 1
    end

    test "list_invocations filters by product_code" do
      assert ToolInvocation.count_invocations(product_code: "SANBASE") == 3
    end

    test "plan filter composes with email search", %{user_pro: user_pro} do
      results =
        ToolInvocation.list_invocations(
          plan_name: "PRO",
          email_search: user_pro.email
        )

      assert length(results) == 2
      assert Enum.all?(results, &(&1.user_id == user_pro.id))
    end

    test "plan filter composes with exclude_team_members" do
      results = ToolInvocation.list_invocations(plan_name: "PRO", exclude_team_members: true)
      assert length(results) == 2
    end

    test "top_by(:plan_name) returns counts per PRODUCT/PLAN combo" do
      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      rows = ToolInvocation.top_by(:plan_name, since)

      assert {"SANBASE/PRO", 2} in rows
      assert {"FREE", 1} in rows
      assert {"SANBASE/MAX", 1} in rows
    end

    test "time_series filters by plan_name" do
      since = DateTime.add(DateTime.utc_now(), -3600, :second)
      rows = ToolInvocation.time_series(since: since, bucket: "day", plan_name: "PRO")

      total = rows |> Enum.map(fn {_, t, _} -> t end) |> Enum.sum()
      assert total == 2
    end

    test "list_invocations filters by plan_combo PRODUCT/PLAN", %{user_pro: user_pro} do
      results = ToolInvocation.list_invocations(plan_combo: "SANBASE/PRO")
      assert length(results) == 2
      assert Enum.all?(results, &(&1.user_id == user_pro.id))

      # A bare plan name (no slash) still works — useful for the FREE bucket
      # where product_code is nil.
      free_results = ToolInvocation.list_invocations(plan_combo: "FREE")
      assert length(free_results) == 1
    end

    test "plan_combos/0 returns distinct PRODUCT/PLAN strings" do
      combos = ToolInvocation.plan_combos()
      assert "SANBASE/PRO" in combos
      assert "FREE" in combos
      assert "SANBASE/MAX" in combos
    end
  end

  defp create_invocation_with_plan(user, plan_name, product_code) do
    ToolInvocation.create(%{
      user_id: user.id,
      tool_name: "fetch_metric_data_tool",
      params: %{},
      is_successful: true,
      duration_ms: 5,
      plan_name: plan_name,
      product_code: product_code
    })
  end

  defp create_basic_invocation(user) do
    ToolInvocation.create(%{
      user_id: user && user.id,
      tool_name: "fetch_metric_data_tool",
      params: %{},
      is_successful: true,
      duration_ms: 5
    })
  end

  defp seed_invocation(user, datetime) do
    {:ok, inv} =
      ToolInvocation.create(%{
        user_id: user.id,
        tool_name: "fetch_metric_data_tool",
        params: %{},
        is_successful: true,
        duration_ms: 5
      })

    # Backdate inserted_at to control bucket placement.
    naive = DateTime.to_naive(datetime) |> NaiveDateTime.truncate(:second)
    inv |> Ecto.Changeset.change(%{inserted_at: naive}) |> Repo.update!()
  end
end
