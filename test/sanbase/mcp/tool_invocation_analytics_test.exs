defmodule Sanbase.MCP.ToolInvocationAnalyticsTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.MCP.ToolInvocation
  alias Sanbase.Repo

  describe "derive_client_from_user_agent/1" do
    test "nil input returns nil" do
      assert ToolInvocation.derive_client_from_user_agent(nil) == nil
    end

    test "matches Claude" do
      assert ToolInvocation.derive_client_from_user_agent("Claude-User/1.0 (+https://claude.ai)") ==
               "claude"
    end

    test "matches ChatGPT" do
      assert ToolInvocation.derive_client_from_user_agent("ChatGPT-User/1.0") == "chatgpt"
      assert ToolInvocation.derive_client_from_user_agent("OpenAI/1.2.3") == "chatgpt"
    end

    test "matches openai / chatgpt regardless of case and embedded substrings" do
      assert ToolInvocation.derive_client_from_user_agent("openai") == "chatgpt"
      assert ToolInvocation.derive_client_from_user_agent("OPENAI") == "chatgpt"
      assert ToolInvocation.derive_client_from_user_agent("openai-mcp/0.1") == "chatgpt"
      assert ToolInvocation.derive_client_from_user_agent("chatgpt") == "chatgpt"
    end

    test "matches Cursor" do
      assert ToolInvocation.derive_client_from_user_agent("Cursor/0.42 mcp") == "cursor"
    end

    test "unknown UA falls back to raw UA string" do
      assert ToolInvocation.derive_client_from_user_agent("curl/8.4.0") == "curl/8.4.0"
    end

    test "raw UA fallback is truncated to the column size" do
      long = String.duplicate("a", 64)
      assert ToolInvocation.derive_client_from_user_agent(long) == String.duplicate("a", 32)
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
          client: ToolInvocation.derive_client_from_user_agent("Claude-User/1.0"),
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
      user_a = insert(:user)
      user_b = insert(:user)
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
