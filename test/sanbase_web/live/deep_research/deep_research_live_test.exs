defmodule SanbaseWeb.DeepResearchLiveTest do
  @moduledoc """
  LiveView-level tests: mount, submit → streamed events → report, ref staleness,
  cancellation and the runner lifecycle (detach/reattach, pause, continue).

  No agent server: the base URL points at a socket that accepts and never answers,
  so the stream task blocks in `create_thread` while events are sent to the
  `Runner` directly. `:sys.get_state(runner)` after each send forces a broadcast.
  """

  # Not async: rewrites app env, and the runners need the shared sandbox mode.
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.DeepResearch.Fixtures, only: [completed_session: 1, paused_session: 1]

  alias Sanbase.DeepResearch.{Event, Runner, Sessions}
  alias Sanbase.DeepResearch.Sessions.SessionTurn
  alias Sanbase.Repo

  @path "/admin/deep_research"
  @runner_supervisor Sanbase.DeepResearch.RunnerSupervisor

  setup do
    original = Application.get_env(:sanbase, Sanbase.DeepResearch)

    # Accepts connections into the backlog, never responds.
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen)

    Application.put_env(:sanbase, Sanbase.DeepResearch,
      base_url: "http://127.0.0.1:#{port}",
      # No catalog: the stream task's API key lookup would race the sandbox owner.
      mcp_servers: []
    )

    on_exit(fn ->
      :gen_tcp.close(listen)

      case original do
        nil -> Application.delete_env(:sanbase, Sanbase.DeepResearch)
        env -> Application.put_env(:sanbase, Sanbase.DeepResearch, env)
      end
    end)

    # Registered last, so it runs FIRST: runners must die before the sandbox does.
    on_exit(fn -> stop_all_runners() end)

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

  # Runners outlive their watchers by design, so they outlive the test too.
  defp stop_all_runners() do
    for {_, pid, _, _} <- DynamicSupervisor.which_children(@runner_supervisor), is_pid(pid) do
      DynamicSupervisor.terminate_child(@runner_supervisor, pid)
    end
  end

  defp put_pause_grace(ms), do: put_env(:pause_after_disconnect_ms, ms)
  defp put_checkpoint_every(ms), do: put_env(:checkpoint_every_ms, ms)

  defp put_env(key, value) do
    env = Application.get_env(:sanbase, Sanbase.DeepResearch)

    Application.put_env(:sanbase, Sanbase.DeepResearch, Keyword.put(env, key, value))
  end

  # A fresh session's first turn is id 1, echoed as the ref in every event.
  @ref 1

  defp submit(view, query) do
    view
    |> element("#dr-composer")
    |> render_submit(%{"query" => query})
  end

  defp runner_of(user) do
    [session] = Sessions.list_user_sessions(user.id)
    pid = Runner.whereis(session.id)
    assert is_pid(pid)
    {session, pid}
  end

  defp send_sync(runner, message) do
    send(runner, message)
    :sys.get_state(runner)
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

  test "streamed events fold into the current turn, ending in a report", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "What is driving ETH?")
    {_session, runner} = runner_of(user)

    send_sync(
      runner,
      {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning on-chain data"}}}
    )

    assert render(view) =~ "Scanning on-chain data"

    send_sync(
      runner,
      {:dra_event, @ref,
       %Event{activity: %{kind: :search_query, id: "s1", query: "eth gas fees"}}}
    )

    html = render(view)
    assert html =~ "Research"
    assert html =~ "eth gas fees"

    send_sync(
      runner,
      {:dra_event, @ref, %Event{report: "## Findings\n\nFees fell.", phase: :writing}}
    )

    html = render(view)
    assert html =~ "Research report"
    assert html =~ "Fees fell."
  end

  test "events with a stale ref are dropped", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")
    {_session, runner} = runner_of(user)

    send_sync(runner, {:dra_event, @ref + 1, %Event{thinking: %{id: "m1", text: "stale text"}}})

    refute render(view) =~ "stale text"
  end

  test "a state-poll result can complete the turn with a recovered report", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")
    {_session, runner} = runner_of(user)

    send_sync(runner, {:dra_poll, @ref, %{report: "## Recovered report"}})

    assert render(view) =~ "Recovered report"
  end

  test "a stale state-poll result is dropped", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")
    {_session, runner} = runner_of(user)

    send_sync(runner, {:dra_poll, @ref + 1, %{report: "stale poll report"}})

    refute render(view) =~ "stale poll report"
  end

  test "cancel stops the run and later events are dropped", %{conn: conn, user: user} do
    {:ok, view, _html} = live(conn, @path)
    submit(view, "q")
    {_session, runner} = runner_of(user)

    html = render_click(view, "cancel", %{})
    refute html =~ "phx-click=\"cancel\""

    # Events queued behind the cancel must not grow the cancelled turn.
    send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "late event"}}})
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
      assert row.phase == :queued
    end

    test "the first question turns the URL into the session permalink mid-stream", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, @path)

      submit(view, "What is driving ETH?")

      {session, runner} = runner_of(user)
      assert_patch(view, "#{@path}/#{session.id}")

      # The patch must not reset the conversation — still attached, same turn.
      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning"}}})
      html = render(view)
      assert html =~ "Scanning"
      assert html =~ "dr-composer"
    end

    test "a poll-completed turn is persisted with its report", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")
      {_session, runner} = runner_of(user)

      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning"}}})
      send_sync(runner, {:dra_poll, @ref, %{report: "## Recovered report"}})
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

    test "a streaming turn is checkpointed, so an abrupt loss keeps its timeline", %{
      conn: conn,
      user: user
    } do
      # Checkpoint on every event — the interval, not the event kind, keeps writes off
      # the hot path.
      put_checkpoint_every(0)

      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")
      {_session, runner} = runner_of(user)

      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning"}}})
      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m2", text: "Reading"}}})
      render(view)

      assert [row] = Repo.all(SessionTurn)
      # A checkpoint, not the settling write: the turn is still in flight.
      assert row.phase == :queued
      refute row.finished_at
      assert [_scanning, %{"kind" => "thinking", "text" => "Reading"}] = row.timeline
    end

    test "the first event of a turn writes nothing — the row was just created", %{
      conn: conn,
      user: user
    } do
      put_checkpoint_every(0)

      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")
      {_session, runner} = runner_of(user)

      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning"}}})
      render(view)

      assert [%{timeline: []}] = Repo.all(SessionTurn)
    end

    test "a follow-up question lands in the same session", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)

      submit(view, "first question")
      render_click(view, "cancel", %{})
      submit(view, "second question")

      assert [session] = Sessions.list_user_sessions(user.id)
      assert session.title == "first question"

      rows = SessionTurn |> Repo.all() |> Enum.sort_by(& &1.position)
      assert [%{position: 1, phase: :cancelled}, %{position: 2, phase: :queued}] = rows
      assert Enum.all?(rows, &(&1.session_id == session.id))
    end
  end

  describe "runner lifecycle across the LiveView" do
    test "a run survives navigating away and reattaches on return", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "long question")
      {session, runner} = runner_of(user)

      # Leaving only detaches — within the grace period the runner keeps going.
      render_click(view, "new_session", %{})
      assert render(view) =~ "What do you want to research?"
      assert Process.alive?(runner)

      render_click(view, "open_session", %{"id" => session.id})
      assert_patch(view, "#{@path}/#{session.id}")

      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Still going"}}})
      html = render(view)
      assert html =~ "Still going"
      assert html =~ "phx-click=\"cancel\""

      assert [%{phase: :queued}] = Repo.all(SessionTurn)
    end

    test "a second LiveView on the session URL attaches to the streaming run", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")
      {session, runner} = runner_of(user)

      {:ok, reconnected, html} = live(conn, "#{@path}/#{session.id}")
      assert html =~ "loading-spinner"

      send_sync(runner, {:dra_event, @ref, %Event{thinking: %{id: "m1", text: "Scanning"}}})
      assert render(reconnected) =~ "Scanning"
      assert render(view) =~ "Scanning"
    end

    test "with nobody attached the run is paused after the grace period", %{
      conn: conn,
      user: user
    } do
      put_pause_grace(1)
      {:ok, view, _html} = live(conn, @path)
      submit(view, "long question")
      {_session, runner} = runner_of(user)
      ref = Process.monitor(runner)

      render_click(view, "new_session", %{})
      assert render(view) =~ "What do you want to research?"

      assert_receive {:DOWN, ^ref, :process, ^runner, :normal}, 2_000

      assert [row] = Repo.all(SessionTurn)
      assert row.phase == :paused
      assert row.error == nil
      assert row.finished_at
    end

    test "a paused turn offers Continue, which resumes it in place", %{conn: conn, user: user} do
      session = paused_session(user)

      {:ok, view, html} = live(conn, "#{@path}/#{session.id}")

      assert html =~ "Research paused"
      assert html =~ "phx-click=\"continue_turn\""

      html = render_click(view, "continue_turn", %{"id" => "1"})

      assert html =~ "loading-spinner"
      assert html =~ "phx-click=\"cancel\""
      refute html =~ "phx-click=\"continue_turn\""
      # The partial timeline keeps growing in the SAME turn.
      assert html =~ "Scanning on-chain data"

      runner = Runner.whereis(session.id)
      assert is_pid(runner)
      assert :sys.get_state(runner).running

      send_sync(
        runner,
        {:dra_event, @ref, %Event{thinking: %{id: "m2", text: "Resumed research"}}}
      )

      assert render(view) =~ "Resumed research"
    end

    test "continue_turn on a settled turn is a no-op", %{conn: conn, user: user} do
      session = completed_session(user)

      {:ok, view, html} = live(conn, "#{@path}/#{session.id}")
      refute html =~ "phx-click=\"continue_turn\""

      # A crafted event must not start a run on a completed turn.
      html = render_click(view, "continue_turn", %{"id" => "1"})

      refute html =~ "loading-spinner"
      assert Runner.whereis(session.id) == nil
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

      assert [%{id: id}] = Sessions.list_user_sessions(user.id)
      assert id == session.id

      rows = SessionTurn |> Repo.all() |> Enum.sort_by(& &1.position)
      assert [%{position: 1, phase: :completed}, %{position: 2, phase: :queued}] = rows
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

    test "deleting the streaming session also stops its runner", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, @path)
      submit(view, "q")
      {session, runner} = runner_of(user)
      ref = Process.monitor(runner)

      render_click(view, "delete_session", %{"id" => session.id})

      assert_receive {:DOWN, ^ref, :process, ^runner, _}, 2_000
      assert Sessions.list_user_sessions(user.id) == []
      assert render(view) =~ "What do you want to research?"
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

    # The share link must be built from Endpoint.admin_url() (the VPN admin
    # host), not the Endpoint :url config — on the deployed pods those differ,
    # and a PHX_HOST-based link 404s on the non-admin pods. Locally both are
    # localhost, so the env var is what makes them distinguishable here.
    test "the copied share link targets the admin host, not the endpoint host", %{
      conn: conn,
      user: user
    } do
      original = System.get_env("SANTIMENT_ROOT_DOMAIN")
      original_port = System.get_env("SANTIMENT_ADMIN_VPN_SERVICE_PORT")
      System.put_env("SANTIMENT_ROOT_DOMAIN", "santiment.net")
      System.put_env("SANTIMENT_ADMIN_VPN_SERVICE_PORT", "31080")

      on_exit(fn ->
        if original,
          do: System.put_env("SANTIMENT_ROOT_DOMAIN", original),
          else: System.delete_env("SANTIMENT_ROOT_DOMAIN")

        if original_port,
          do: System.put_env("SANTIMENT_ADMIN_VPN_SERVICE_PORT", original_port),
          else: System.delete_env("SANTIMENT_ADMIN_VPN_SERVICE_PORT")
      end)

      session = completed_session(user)
      {:ok, _session} = Sessions.toggle_public(session.id, user.id)

      {:ok, view, _html} = live(conn, @path)

      assert has_element?(
               view,
               ~s|#copy-share-link-#{session.id}[data-copy="http://santiment.net:31080/deep_research/shared/#{session.id}"]|
             )
    end
  end
end
