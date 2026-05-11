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

    test "matches Cursor" do
      assert ToolInvocation.derive_client_from_user_agent("Cursor/0.42 mcp") == "cursor"
    end

    test "unknown UA falls back to other" do
      assert ToolInvocation.derive_client_from_user_agent("curl/8.4.0") == "other"
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

    test "invalid client value is rejected", %{user: user} do
      assert {:error, changeset} =
               ToolInvocation.create(%{
                 user_id: user.id,
                 tool_name: "fetch_metric_data_tool",
                 params: %{},
                 is_successful: true,
                 duration_ms: 10,
                 client: "bogus"
               })

      assert {_, _} = changeset.errors[:client]
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
