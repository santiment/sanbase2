defmodule Sanbase.DeepResearch.RunnerTest do
  @moduledoc """
  Runner unit tests: attach/detach, the pause grace period, continue.

  Every runner is EPHEMERAL (no session_id), so nothing touches the DB — persistence
  is covered in `SanbaseWeb.DeepResearchLiveTest`. The base URL points at a listener
  that never answers, so a run stays in flight until settled.
  """

  use ExUnit.Case, async: false

  alias Sanbase.DeepResearch.{EventParser, Failure, Runner, Timeline, Turn}

  @supervisor Sanbase.DeepResearch.RunnerSupervisor
  @started_key :runner_test_started

  setup do
    original = Application.get_env(:sanbase, Sanbase.DeepResearch)

    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false])
    {:ok, port} = :inet.port(listen)

    Application.put_env(:sanbase, Sanbase.DeepResearch,
      base_url: "http://127.0.0.1:#{port}",
      mcp_servers: []
    )

    # Unlinked: `on_exit` runs after the test process dies, so the cleanup list cannot
    # live in that process.
    {:ok, started} = Agent.start(fn -> [] end)
    Process.put(@started_key, started)

    on_exit(fn ->
      # Only this test's runners (the supervisor is shared), and before the port, which
      # one of them may still hold.
      for pid <- Agent.get(started, & &1), Process.alive?(pid) do
        DynamicSupervisor.terminate_child(@supervisor, pid)
      end

      Agent.stop(started)
      :gen_tcp.close(listen)

      case original do
        nil -> Application.delete_env(:sanbase, Sanbase.DeepResearch)
        env -> Application.put_env(:sanbase, Sanbase.DeepResearch, env)
      end
    end)

    :ok
  end

  defp put_pause_grace(ms) do
    env = Application.get_env(:sanbase, Sanbase.DeepResearch)

    Application.put_env(
      :sanbase,
      Sanbase.DeepResearch,
      Keyword.put(env, :pause_after_disconnect_ms, ms)
    )
  end

  defp start_runner(overrides \\ []) do
    key = "runner-test-#{System.unique_integer([:positive])}"

    {:ok, pid} =
      Runner.ensure_started(%{
        key: key,
        session_id: nil,
        user: nil,
        model_tier: "mid",
        thread_id: Keyword.get(overrides, :thread_id),
        next_id: 1
      })

    Agent.update(Process.get(@started_key), &[pid | &1])

    {key, pid}
  end

  describe "event-silence watchdog" do
    test "each event re-arms the timer and the timer asks for the run status" do
      env = Application.get_env(:sanbase, Sanbase.DeepResearch)

      Application.put_env(
        :sanbase,
        Sanbase.DeepResearch,
        Keyword.put(env, :event_silence_ms, 60_000)
      )

      {_key, pid} = start_runner(thread_id: "t1")
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")
      first = :sys.get_state(pid).silence_timer
      assert is_reference(first)

      send(pid, {:dra_event, 1, %{run_id: "r1", phase: :researching}})
      assert :sys.get_state(pid).silence_timer != first
      assert :sys.get_state(pid).run_id == "r1"
    end

    test "a run the server reports as over settles the turn as paused and stops the stream" do
      {key, pid} = start_runner(thread_id: "t1")
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")
      send(pid, {:dra_event, 1, %{run_id: "r1", phase: :researching}})

      send(pid, {:dra_run_status, 1, {:ok, %{"status" => "error"}}})

      assert_receive {:dra_runner, ^key,
                      %{running: false, current_turn: %Turn{phase: :paused, error: error}}}

      assert error =~ "ended (error)"
      assert :sys.get_state(pid).task == nil
    end

    test "a run still running server-side changes nothing" do
      {_key, pid} = start_runner(thread_id: "t1")
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      send(pid, {:dra_run_status, 1, {:ok, %{"status" => "running"}}})
      :sys.get_state(pid)

      assert :sys.get_state(pid).running == true
    end

    test "a status for a superseded turn is ignored" do
      {_key, pid} = start_runner(thread_id: "t1")
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      send(pid, {:dra_run_status, 99, {:ok, %{"status" => "error"}}})
      :sys.get_state(pid)

      assert :sys.get_state(pid).running == true
    end
  end

  test "ensure_started is idempotent per key" do
    {key, pid} = start_runner()

    assert {:ok, ^pid} =
             Runner.ensure_started(%{key: key, session_id: nil, user: nil, next_id: 1})

    assert Runner.whereis(key) == pid
  end

  test "attach returns the current snapshot; ask starts a run and broadcasts" do
    {key, pid} = start_runner()

    assert {:ok, snapshot} = Runner.attach(pid, self())
    assert snapshot.key == key
    assert snapshot.running == false
    assert snapshot.current_turn == nil

    assert {:ok, snapshot} = Runner.ask(pid, "What is driving ETH?")
    assert snapshot.running == true

    assert %Turn{id: 1, question: "What is driving ETH?", phase: :queued} =
             snapshot.current_turn

    send(pid, {:dra_event, 1, %{thinking: %{id: "m1", text: "Scanning"}}})

    assert_receive {:dra_runner, ^key, %{current_turn: %Turn{timeline: [%{text: "Scanning"}]}}}
  end

  test "every event stamps the turn's last_event_at" do
    {key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, %{current_turn: %Turn{last_event_at: nil}}} = Runner.ask(pid, "q")

    send(pid, {:dra_event, 1, %{phase: :researching}})

    # The ask itself broadcasts a snapshot too (last_event_at nil) — wait for the stamped one.
    assert_receive {:dra_runner, ^key, %{current_turn: %Turn{last_event_at: at}}}
                   when is_integer(at)
  end

  test "ask while a run streams is busy" do
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, _} = Runner.ask(pid, "first")

    assert {:error, :busy} = Runner.ask(pid, "second")
  end

  test "cancel settles the turn; later events are dropped" do
    {key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, _} = Runner.ask(pid, "q")

    assert {:ok, snapshot} = Runner.cancel(pid)
    assert snapshot.running == false
    assert snapshot.current_turn.phase == :cancelled

    send(pid, {:dra_event, 1, %{thinking: %{id: "m1", text: "late event"}}})
    :sys.get_state(pid)

    refute_receive {:dra_runner, ^key, %{current_turn: %Turn{timeline: [_ | _]}}}
  end

  test "an idle runner stops as soon as its last watcher detaches" do
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    ref = Process.monitor(pid)

    Runner.detach(pid, self())

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 1_000
  end

  test "a streaming runner pauses (and stops) once the grace period expires" do
    put_pause_grace(1)
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, _} = Runner.ask(pid, "q")
    ref = Process.monitor(pid)

    Runner.detach(pid, self())

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end

  test "reattaching within the grace period cancels the pause" do
    # Explicit, so shortening the default grace cannot make this race.
    put_pause_grace(60_000)
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, _} = Runner.ask(pid, "q")

    Runner.detach(pid, self())
    assert :sys.get_state(pid).pause_timer != nil

    {:ok, snapshot} = Runner.attach(pid, self())
    assert :sys.get_state(pid).pause_timer == nil
    assert snapshot.running == true
    assert Process.alive?(pid)
  end

  test "a watcher dying counts as a detach" do
    put_pause_grace(1)
    {_key, pid} = start_runner()

    watcher = spawn(fn -> Process.sleep(:infinity) end)
    {:ok, _} = Runner.attach(pid, watcher)
    {:ok, _} = Runner.ask(pid, "q")
    ref = Process.monitor(pid)

    Process.exit(watcher, :kill)

    assert_receive {:DOWN, ^ref, :process, ^pid, :normal}, 2_000
  end

  describe "a run that ends in a failure" do
    defp end_run(pid, failure) do
      send(pid, {:sys.get_state(pid).task.ref, {:error, failure}})
    end

    defp timeout(), do: %Req.TransportError{reason: :timeout}
    defp refused(), do: %Req.TransportError{reason: :econnrefused}

    test "parks the turn :paused when the connection broke — it is resumable" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      end_run(pid, Failure.connection("create_thread", "http://127.0.0.1:1", refused()))

      assert_receive {:dra_runner, ^key, %{running: false, current_turn: turn}}
      assert %Turn{phase: :paused, error: error} = turn
      assert error =~ "nothing is listening"
    end

    test "fails the turn when the agent itself answered" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      end_run(pid, Failure.response("The run", 500, "boom"))

      assert_receive {:dra_runner, ^key, %{current_turn: %Turn{phase: :failed, error: error}}}
      assert error =~ "HTTP 500"
    end

    test "parks the turn :paused when the state poll could not be made" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      # Stream over with no report: the turn waits on the thread's state.
      send(pid, {:dra_thread, "th1"})
      send(pid, {:sys.get_state(pid).task.ref, :ok})

      send(pid, {:dra_poll, 1, Failure.connection("get_state", "http://x", timeout())})

      assert_receive {:dra_runner, ^key, %{current_turn: %Turn{phase: :paused, error: error}}}
      assert error =~ "timed out"
      # NOT the "finished without producing a report" verdict — we never asked.
      refute error =~ "without producing a report"
    end

    test "a turn still :queued when the stream ends is failed as never started" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      # Only heartbeats came back: no worker ever emitted the run's metadata event.
      send(pid, {:dra_thread, "th1"})
      send(pid, {:sys.get_state(pid).task.ref, :ok})
      send(pid, {:dra_poll, 1, %{}})

      assert_receive {:dra_runner, ^key, %{current_turn: %Turn{phase: :failed, error: error}}}
      assert error =~ "never started this run"
      refute error =~ "without a report"
    end

    test "a turn the agent did pick up but never reported on gets the no-report verdict" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      send(pid, {:dra_thread, "th1"})
      send(pid, {:dra_event, 1, EventParser.parse(%{"run_id" => "r1", "attempt" => 1})})
      send(pid, {:sys.get_state(pid).task.ref, :ok})
      send(pid, {:dra_poll, 1, %{}})

      assert_receive {:dra_runner, ^key, %{current_turn: %Turn{phase: :failed, error: error}}}
      assert error =~ "without a report"
      refute error =~ "never started"
    end

    test "parks the turn :paused when the stream task itself died" do
      {key, pid} = start_runner()
      {:ok, _} = Runner.attach(pid, self())
      {:ok, _} = Runner.ask(pid, "q")

      task = :sys.get_state(pid).task
      Process.exit(task.pid, :kill)

      assert_receive {:dra_runner, ^key, %{current_turn: %Turn{phase: :paused, error: error}}}
      assert error =~ "stopped unexpectedly"
    end
  end

  test "continue resumes a paused turn in place" do
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())

    paused = %{Timeline.new_turn("ETH drivers?", 1, 123) | phase: :paused, finished_at: 456}

    assert {:ok, snapshot} = Runner.continue(pid, paused)
    assert snapshot.running == true
    assert %Turn{id: 1, phase: :queued, finished_at: nil, error: nil} = snapshot.current_turn

    # The resume run streams into the SAME turn id.
    send(pid, {:dra_event, 1, %{thinking: %{id: "m1", text: "Resumed"}}})
    :sys.get_state(pid)
    assert_receive {:dra_runner, _key, %{current_turn: %Turn{timeline: [%{text: "Resumed"}]}}}
  end

  test "continue settles the unrelated turn it replaces" do
    {key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    {:ok, _} = Runner.ask(pid, "first")

    # Land turn 1 in "not running, not settled": stream over, poll never answers.
    send(pid, {:dra_thread, "th1"})
    task_ref = :sys.get_state(pid).task.ref
    send(pid, {task_ref, :ok})
    refute :sys.get_state(pid).running

    paused = %{Timeline.new_turn("another question", 7, 123) | phase: :paused}
    assert {:ok, %{current_turn: %Turn{id: 7}}} = Runner.continue(pid, paused)

    # Nothing else would have settled turn 1 once :current_turn moved on.
    assert_receive {:dra_runner, ^key, %{current_turn: %Turn{id: 1, phase: :failed}}}
  end

  test "continue rejects a turn that is not paused" do
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())

    settled = %{Timeline.new_turn("q", 1, 123) | phase: :completed}

    assert {:error, :not_paused} = Runner.continue(pid, settled)
    assert {:ok, %{running: false}} = Runner.attach(pid, self())
  end

  test "calls against a dead runner return not_alive instead of exiting" do
    {_key, pid} = start_runner()
    {:ok, _} = Runner.attach(pid, self())
    ref = Process.monitor(pid)
    Runner.shutdown(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 1_000

    assert {:error, :not_alive} = Runner.ask(pid, "q")
    assert {:error, :not_alive} = Runner.attach(pid, self())
    assert {:error, :not_alive} = Runner.cancel(pid)
  end

  # -- leftover runs on the thread -----------------------------------------------------

  # The agent server resumes in-flight runs from disk after a restart, with no client
  # attached; a new turn on that thread would otherwise queue behind such a run for good.
  test "starting a turn on an existing thread cancels whatever is still active there" do
    port = start_fake_agent_server(self())
    env = Application.get_env(:sanbase, Sanbase.DeepResearch)

    Application.put_env(
      :sanbase,
      Sanbase.DeepResearch,
      Keyword.put(env, :base_url, "http://127.0.0.1:#{port}")
    )

    {_key, pid} = start_runner(thread_id: "t-leftover")
    assert {:ok, _snapshot} = Runner.ask(pid, "follow-up")

    # Only this thread's traffic: a runner from an earlier test may still be finishing
    # a request through whatever base_url is configured by the time it retries.
    requests = for _ <- 1..3, do: next_fake_agent_request("/threads/t-leftover")

    assert requests == [
             {:GET, "/threads/t-leftover/runs"},
             {:POST, "/threads/t-leftover/runs/zombie/cancel"},
             {:POST, "/threads/t-leftover/runs/stream"}
           ]
  end

  defp next_fake_agent_request(prefix) do
    receive do
      {:fake_agent_request, method, path} ->
        if String.starts_with?(path, prefix),
          do: {method, path},
          else: next_fake_agent_request(prefix)
    after
      5_000 -> flunk("the runner made no further request to the agent server")
    end
  end

  # A minimal HTTP/1.1 agent server: reports every request line to `test_pid`, lists one
  # running run, accepts its cancel, and never answers the stream so the turn stays in
  # flight. One connection at a time is enough — every answer closes its connection, and
  # the stream request is the last one made.
  defp start_fake_agent_server(test_pid) do
    {:ok, listen} = :gen_tcp.listen(0, [:binary, active: false, packet: :http_bin])
    {:ok, port} = :inet.port(listen)
    spawn_link(fn -> fake_agent_accept(listen, test_pid) end)
    port
  end

  defp fake_agent_accept(listen, test_pid) do
    {:ok, sock} = :gen_tcp.accept(listen)

    {:ok, {:http_request, method, {:abs_path, path}, _version}} =
      :gen_tcp.recv(sock, 0, 5_000)

    body_length = drain_headers(sock, 0)
    send(test_pid, {:fake_agent_request, method, path})

    cond do
      method == :GET ->
        fake_agent_reply(sock, body_length, ~s([{"run_id":"zombie","status":"running"}]))

      String.ends_with?(path, "/cancel") ->
        fake_agent_reply(sock, body_length, "{}")

      # The stream: never answered; the socket stays open as long as this process lives.
      true ->
        :ok
    end

    fake_agent_accept(listen, test_pid)
  end

  defp drain_headers(sock, body_length) do
    case :gen_tcp.recv(sock, 0, 5_000) do
      {:ok, :http_eoh} ->
        body_length

      {:ok, {:http_header, _, :"Content-Length", _, len}} ->
        drain_headers(sock, String.to_integer(len))

      {:ok, {:http_header, _, _, _, _}} ->
        drain_headers(sock, body_length)
    end
  end

  # Read the request body before answering: closing with unread input can reset the
  # connection and drop the reply, which the client would then retry.
  defp fake_agent_reply(sock, body_length, body) do
    :ok = :inet.setopts(sock, packet: :raw)
    if body_length > 0, do: {:ok, _} = :gen_tcp.recv(sock, body_length, 5_000)

    :ok =
      :gen_tcp.send(
        sock,
        "HTTP/1.1 200 OK\r\ncontent-type: application/json\r\n" <>
          "content-length: #{byte_size(body)}\r\nconnection: close\r\n\r\n" <> body
      )

    :gen_tcp.close(sock)
  end
end
