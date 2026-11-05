defmodule SanbaseWeb.Admin.AiReviewApiControllerTest do
  use SanbaseWeb.ConnCase, async: false

  import Sanbase.Factory

  alias Sanbase.Accounts.{Apikey, UserRole}
  alias Sanbase.DiscordBot.AiContext

  @base_params %{
    discord_user: "tg:balance54",
    guild_id: "tg_-1001140094437",
    guild_name: "Santiment",
    channel_id: "854002386375934033",
    channel_name: "general",
    thread_id: "tg_-1001140094437_m96763",
    command: "!ai",
    question: "Ok, do the same for the top 200",
    answer: "I can't give a reliable top-200 list for that window.",
    elapsed_time: 12.0,
    tool_issues: ["fetch_metric_data_tool:error"],
    langfuse_trace_id: "f3be602d-761d-423a-b66d-e9ace00ea14c"
  }

  setup do
    {:ok, context} = AiContext.create(@base_params)
    %{context: context}
  end

  defp api_conn(role_factory) do
    user = insert(:user)

    if role_factory do
      role = insert(role_factory)
      {:ok, _} = UserRole.create(user.id, role.id)
    end

    {:ok, apikey} = Apikey.generate_apikey(user)
    put_req_header(build_conn(), "authorization", "Apikey " <> apikey)
  end

  test "rejects calls without credentials" do
    conn = get(build_conn(), "/admin_api/ai_review/issues")
    assert json_response(conn, 401)["error"] =~ "API key"
  end

  test "rejects users without an Admin Panel role" do
    conn = get(api_conn(nil), "/admin_api/ai_review/issues")
    assert json_response(conn, 403)["error"] =~ "Admin Panel role"
  end

  test "a viewer lists issues with their latest turn and a cursor", %{context: context} do
    conn = api_conn(:role_admin_panel_viewer)
    body = json_response(get(conn, "/admin_api/ai_review/issues?status=open"), 200)

    assert [issue] = body["issues"]
    assert issue["signature"] == "tool_issue:fetch_metric_data_tool:error"
    assert issue["status"] == "open"
    assert issue["latest_turn"]["id"] == context.id
    assert issue["latest_turn"]["langfuse_url"] =~ "/traces/f3be602d-761d-423a-b66d-e9ace00ea14c"

    conn = get(conn, "/admin_api/ai_review/issues", since: body["next_since"])
    assert json_response(conn, 200)["issues"] == []
  end

  test "rejects an unknown status" do
    conn = get(api_conn(:role_admin_panel_viewer), "/admin_api/ai_review/issues?status=done")
    assert json_response(conn, 400)["error"] =~ "Unknown status done"
  end

  test "shows one issue with its turns", %{context: context} do
    conn = api_conn(:role_admin_panel_viewer)
    [issue] = json_response(get(conn, "/admin_api/ai_review/issues"), 200)["issues"]

    body = json_response(get(conn, "/admin_api/ai_review/issues/#{issue["id"]}"), 200)
    assert [turn] = body["turns"]
    assert turn["id"] == context.id
    assert turn["question"] == "Ok, do the same for the top 200"

    assert json_response(get(conn, "/admin_api/ai_review/issues/999999"), 404)
  end

  test "a viewer cannot resolve an issue" do
    conn = api_conn(:role_admin_panel_viewer)
    [issue] = json_response(get(conn, "/admin_api/ai_review/issues"), 200)["issues"]

    conn = post(conn, "/admin_api/ai_review/issues/#{issue["id"]}/resolve", %{note: "fixed"})
    assert json_response(conn, 403)["error"] =~ "Editor or Owner"
  end

  test "an editor resolves and reopens an issue" do
    conn = api_conn(:role_admin_panel_editor)
    [issue] = json_response(get(conn, "/admin_api/ai_review/issues"), 200)["issues"]

    resolved =
      conn
      |> post("/admin_api/ai_review/issues/#{issue["id"]}/resolve", %{note: "PR 5413"})
      |> json_response(200)

    assert resolved["issue"]["status"] == "resolved"
    assert resolved["issue"]["resolution_note"] == "PR 5413"
    assert resolved["issue"]["resolved_by"]["id"]

    reopened =
      conn
      |> post("/admin_api/ai_review/issues/#{issue["id"]}/reopen")
      |> json_response(200)

    assert reopened["issue"]["status"] == "open"
  end
end
