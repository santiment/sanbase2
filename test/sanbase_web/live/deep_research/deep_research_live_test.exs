defmodule SanbaseWeb.DeepResearchLiveTest do
  @moduledoc """
  LiveView-level tests for the deep research UI: mount, the submit → streamed
  events → report flow, ref staleness, and cancellation.

  No agent server is involved. The base URL points at a local TCP socket that
  accepts and never answers, so the async `create_thread` call blocks for the
  duration of each test — the current turn stays alive and the streamed-event
  handlers are driven deterministically with hand-sent `{:dra_event, ref, result}`
  / `{:dra_poll, ref, result}` messages (exactly what `Client.stream_run` and the
  poll task send).
  """

  # Not async: rewrites the Sanbase.DeepResearch app env.
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.DeepResearch.Fixtures, only: [completed_session: 1]

  alias Sanbase.DeepResearch.Sessions
  alias Sanbase.DeepResearch.Sessions.SessionTurn
  alias Sanbase.Repo

  @path "/admin/deep_research"

  setup do
    original = Application.get_env(:sanbase, Sanbase.DeepResearch)

    # A listener that accepts connections (into the backlog) but never responds.
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen)

    Application.put_env(:sanbase, Sanbase.DeepResearch,
      base_url: "http://127.0.0.1:#{port}",
      # No MCP catalog: the async task must not resolve API keys (a DB read from
      # a process outside the sandbox owner's tree).
      mcp_servers: []
    )

    on_exit(fn ->
      :gen_tcp.close(listen)

      case original do
        nil -> Application.delete_env(:sanbase, Sanbase.DeepResearch)
        env -> Application.put_env(:sanbase, Sanbase.DeepResearch, env)
      end
    end)

    {conn, user} = admin_conn()
    {:ok, conn: conn, user: user}
  end

  defp admin_conn() do
    user = Sanbase.Factory.insert(:user)
    role = Sanbase.Factory.insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    {Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens), user}
  end

  # The first turn of a fresh LiveView always gets id 1 — the ref echoed back in
  # every {:dra_event, ref, _} message.
  @ref 1

  defp submit(view, query) do
    view
    |> element("#dr-composer")
    |> render_submit(%{"query" => query})
  end

  test "mounts with the empty state", %{conn: conn} do
    {:ok, _view, html} = live(conn, @path)

    assert html =~ "What do you want to research?"
  end

  test "submit shows the question, a spinner and a stop affordance", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    html = submit(view, "What is driving ETH?")

    assert html =~ "What is driving ETH?"
    assert html =~ "loading-spinner"
    assert html =~ "phx-click=\"cancel\""
  end

  test "streamed events fold into the current turn, ending in a report", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "What is driving ETH?")

    send(view.pid, {:dra_event, @ref, %{thinking: %{id: "m1", text: "Scanning on-chain data"}}})
    assert render(view) =~ "Scanning on-chain data"

    send(
      view.pid,
      {:dra_event, @ref, %{activity: %{kind: :search_query, id: "s1", query: "eth gas fees"}}}
    )

    html = render(view)
    assert html =~ "Research"
    assert html =~ "eth gas fees"

    send(view.pid, {:dra_event, @ref, %{report: "## Findings\n\nFees fell.", phase: :writing}})
    html = render(view)
    assert html =~ "Research report"
    assert html =~ "Fees fell."
  end

  test "events with a stale ref are dropped", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")

    send(view.pid, {:dra_event, @ref + 1, %{thinking: %{id: "m1", text: "stale text"}}})

    refute render(view) =~ "stale text"
  end

  test "a state-poll result can complete the turn with a recovered report", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")

    send(view.pid, {:dra_poll, @ref, %{report: "## Recovered report"}})

    assert render(view) =~ "Recovered report"
  end

  test "a stale state-poll result is dropped", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")

    send(view.pid, {:dra_poll, @ref + 1, %{report: "stale poll report"}})

    refute render(view) =~ "stale poll report"
  end

  test "cancel stops the run and later events are dropped", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")

    html = render_click(view, "cancel", %{})
    refute html =~ "phx-click=\"cancel\""

    # Events queued behind the cancel must not grow the cancelled turn.
    send(view.pid, {:dra_event, @ref, %{thinking: %{id: "m1", text: "late event"}}})
    refute render(view) =~ "late event"
  end

  test "a cancel with no run in flight is a no-op", %{conn: conn} do
    {:ok, view, _html} = live(conn, @path)

    # Never submitted — a crafted/duplicate cancel must not crash or change state.
    html = render_click(view, "cancel", %{})

    assert html =~ "What do you want to research?"
  end

  describe "session persistence" do
    test "submit creates a session with a pending turn row", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)

      submit(view, "What is driving ETH?")

      assert [session] = Sessions.list_user_sessions(user.id)
      assert session.title == "What is driving ETH?"
      assert session.is_public == false

      assert [row] = Repo.all(SessionTurn)
      assert row.session_id == session.id
      assert row.position == 1
      assert row.question == "What is driving ETH?"
      assert row.phase == :planning
    end

    test "the first question turns the URL into the session permalink mid-stream", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, @path)

      submit(view, "What is driving ETH?")

      assert [session] = Sessions.list_user_sessions(user.id)
      assert_patch(view, "#{@path}/#{session.id}")

      # The patch must NOT reset the conversation: the live run keeps
      # streaming into the same process.
      send(view.pid, {:dra_event, @ref, %{thinking: %{id: "m1", text: "Scanning"}}})
      html = render(view)
      assert html =~ "Scanning"
      assert html =~ "dr-composer"
    end

    test "a poll-completed turn is persisted with its report", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")

      send(view.pid, {:dra_event, @ref, %{thinking: %{id: "m1", text: "Scanning"}}})
      send(view.pid, {:dra_poll, @ref, %{report: "## Recovered report"}})
      render(view)

      assert [row] = Repo.all(SessionTurn)
      assert row.phase == :completed
      assert row.report =~ "Recovered report"
      assert row.finished_at
      assert [%{"kind" => "thinking", "text" => "Scanning"}] = row.timeline
    end

    test "cancel persists the cancelled turn", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")

      render_click(view, "cancel", %{})

      assert [row] = Repo.all(SessionTurn)
      assert row.phase == :cancelled
      assert row.finished_at
    end

    test "a follow-up question lands in the same session", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)

      submit(view, "first question")
      render_click(view, "cancel", %{})
      submit(view, "second question")

      assert [session] = Sessions.list_user_sessions(user.id)
      assert session.title == "first question"

      rows = SessionTurn |> Repo.all() |> Enum.sort_by(& &1.position)
      assert [%{position: 1, phase: :cancelled}, %{position: 2, phase: :planning}] = rows
      assert Enum.all?(rows, &(&1.session_id == session.id))
    end
  end

  describe "history sidebar and reopened sessions" do
    test "the sidebar lists past sessions", %{conn: conn, user: user} do
      session = completed_session(user)

      {:ok, _view, html} = live(conn, @path)

      assert html =~ "ETH drivers?"
      assert html =~ session.id
    end

    test "opening a session by URL shows its history with the composer ready", %{
      conn: conn,
      user: user
    } do
      session = completed_session(user)

      {:ok, _view, html} = live(conn, "#{@path}/#{session.id}")

      assert html =~ "Fees fell."
      assert html =~ "dr-composer"
    end

    test "clicking a sidebar session patches into it", %{conn: conn, user: user} do
      session = completed_session(user)
      {:ok, view, _html} = live(conn, @path)

      render_click(view, "open_session", %{"id" => session.id})

      assert_patch(view, "#{@path}/#{session.id}")
      html = render(view)
      assert html =~ "Fees fell."
      assert html =~ "dr-composer"
    end

    test "the owner can continue a reopened session", %{conn: conn, user: user} do
      session = completed_session(user)
      {:ok, view, _html} = live(conn, "#{@path}/#{session.id}")

      submit(view, "And what about SOL?")

      # The follow-up appends to the same session — no new session is created.
      assert [%{id: id}] = Sessions.list_user_sessions(user.id)
      assert id == session.id

      rows = SessionTurn |> Repo.all() |> Enum.sort_by(& &1.position)
      assert [%{position: 1, phase: :completed}, %{position: 2, phase: :planning}] = rows
      assert Enum.all?(rows, &(&1.session_id == session.id))
      assert render(view) =~ "And what about SOL?"
    end

    test "someone else's session redirects away without leaking it", %{conn: conn} do
      other = Sanbase.Factory.insert(:user)
      session = completed_session(other)

      assert {:error, {:live_redirect, %{to: @path}}} = live(conn, "#{@path}/#{session.id}")
    end

    test "an unknown session id redirects away", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: @path}}} =
               live(conn, "#{@path}/#{Ecto.UUID.generate()}")
    end

    test "deleting a session removes it from the sidebar and the database", %{
      conn: conn,
      user: user
    } do
      session = completed_session(user)
      {:ok, view, _html} = live(conn, @path)

      html = render_click(view, "delete_session", %{"id" => session.id})

      refute html =~ "ETH drivers?"
      assert Sessions.list_user_sessions(user.id) == []
    end

    test "toggle_public flips the share flag and reveals the share link", %{
      conn: conn,
      user: user
    } do
      session = completed_session(user)
      {:ok, view, html} = live(conn, @path)
      refute html =~ "copy-share-link-#{session.id}"

      html = render_click(view, "toggle_public", %{"id" => session.id})

      assert html =~ "copy-share-link-#{session.id}"
      assert html =~ "/deep_research/shared/#{session.id}"
      assert [%{is_public: true}] = Sessions.list_user_sessions(user.id)

      html = render_click(view, "toggle_public", %{"id" => session.id})
      refute html =~ "copy-share-link-#{session.id}"
    end

    test "navigating away from a streaming run cancels and persists it", %{conn: conn} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "long question")

      render_click(view, "new_session", %{})

      assert [row] = Repo.all(SessionTurn)
      assert row.phase == :cancelled
      assert render(view) =~ "What do you want to research?"
    end
  end
end
