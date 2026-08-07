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

    {:ok, conn: admin_conn()}
  end

  defp admin_conn() do
    user = Sanbase.Factory.insert(:user)
    role = Sanbase.Factory.insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)

    Plug.Test.init_test_session(Phoenix.ConnTest.build_conn(), jwt_tokens)
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
end
