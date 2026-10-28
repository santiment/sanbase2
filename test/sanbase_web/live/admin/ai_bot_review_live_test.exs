defmodule SanbaseWeb.Admin.AiBotReviewLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.DiscordBot.AiContext

  @base_params %{
    discord_user: "someone",
    guild_id: "852836083381174282",
    guild_name: "Santiment",
    channel_id: "854002386375934033",
    thread_id: "1564953330311110757",
    question: "Why did the crypto market drop over the last 3 days?",
    answer: "The market fell on Fed uncertainty."
  }

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  defp create_turn(params) do
    {:ok, context} = AiContext.create(Map.merge(@base_params, params))
    context
  end

  test "lists flagged turns and hides clean ones by default", %{conn: conn} do
    failed = create_turn(%{delivery_status: "failed", langfuse_trace_id: "78b51dcb"})
    clean = create_turn(%{delivery_status: "sent"})

    {:ok, view, _html} = live(conn, "/admin/ai_bot_review")

    assert has_element?(view, "h1", "AI Bot Review")
    assert has_element?(view, "#rows-#{failed.id}", "Delivery failed")
    assert has_element?(view, "#rows-#{failed.id} a[href$='78b51dcb']", "Langfuse")
    refute has_element?(view, "#rows-#{clean.id}")
    assert has_element?(view, "#flag-count-delivery_failed", "1")
  end

  test "shows every turn when flagged only is off", %{conn: conn} do
    clean = create_turn(%{delivery_status: "sent"})

    {:ok, view, _html} = live(conn, "/admin/ai_bot_review?flagged_only=false")

    assert has_element?(view, "#rows-#{clean.id}")
  end

  test "picking a flag narrows the list", %{conn: conn} do
    failed = create_turn(%{delivery_status: "failed"})
    slow = create_turn(%{elapsed_time: 90.0})

    {:ok, view, _html} = live(conn, "/admin/ai_bot_review")

    view |> element("#flag-count-slow") |> render_click()

    assert has_element?(view, "#rows-#{slow.id}")
    refute has_element?(view, "#rows-#{failed.id}")
  end

  test "opens the full turn", %{conn: conn} do
    context =
      create_turn(%{
        status: "degraded",
        answer: "A long answer.",
        tool_issues: ["search_tweets:empty"]
      })

    {:ok, view, _html} = live(conn, "/admin/ai_bot_review")

    view |> element("#show-#{context.id}") |> render_click()

    assert has_element?(view, "#review-details", "A long answer.")
    assert has_element?(view, "#review-details", "search_tweets:empty")

    view |> element("#close-details") |> render_click()
    refute has_element?(view, "#review-details")
  end

  test "export downloads the filtered rows as JSONL", %{conn: conn} do
    failed = create_turn(%{delivery_status: "failed"})
    _clean = create_turn(%{delivery_status: "sent"})

    conn = get(conn, "/admin/ai_bot_review/export")

    assert get_resp_header(conn, "content-type") |> hd() =~ "application/x-ndjson"
    assert get_resp_header(conn, "content-disposition") |> hd() =~ ".jsonl"
    assert [line] = conn |> response(200) |> String.split("\n", trim: true)
    assert Jason.decode!(line)["id"] == failed.id
  end
end
