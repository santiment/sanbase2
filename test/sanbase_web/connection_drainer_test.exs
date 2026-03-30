defmodule SanbaseWeb.ConnectionDrainerTest do
  # async: false because we use Mock which replaces modules globally
  use ExUnit.Case, async: false

  import Mock

  defmodule SlowPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      Process.sleep(1_000)

      conn
      |> put_resp_header("connection", "close")
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "ok")
    end
  end

  defp start_server!(plug) do
    bandit_opts = [plug: plug, port: 0, startup_log: false]
    pid = start_supervised!({Bandit, bandit_opts})
    {:ok, {_ip, port}} = ThousandIsland.listener_info(pid)
    {pid, port}
  end

  defp start_drainer!(server_pid) do
    with_bandit_mock(server_pid, fn ->
      start_supervised!(
        Supervisor.child_spec(
          {SanbaseWeb.ConnectionDrainer,
           endpoint: __MODULE__, shutdown: 10_000, name: :test_drainer},
          restart: :temporary
        )
      )
    end)
  end

  # Mock Bandit.PhoenixAdapter.bandit_pid/2 to return our test server pid
  # instead of looking up a real Phoenix Endpoint supervisor.
  defp with_bandit_mock(server_pid, fun) do
    with_mock Bandit.PhoenixAdapter, [:passthrough],
      bandit_pid: fn _endpoint, _scheme -> {:ok, server_pid} end do
      fun.()
    end
  end

  test "waits for in-flight requests to complete before stop returns" do
    {server_pid, port} = start_server!(SlowPlug)
    _drainer = start_drainer!(server_pid)

    test_pid = self()

    # Start a slow request in a separate process
    request_task =
      Task.async(fn ->
        send(test_pid, :request_started)
        Req.get!("http://127.0.0.1:#{port}/")
      end)

    assert_receive :request_started, 1_000
    # Give Bandit a moment to accept the connection
    Process.sleep(100)

    # Stop the drainer — this calls terminate/2 which should block
    # until the in-flight request completes
    with_bandit_mock(server_pid, fn ->
      stop_task = Task.async(fn -> GenServer.stop(:test_drainer, :normal, 10_000) end)

      # The stop should NOT complete immediately because the request is still running
      refute Task.yield(stop_task, 200)

      # The in-flight request should complete successfully despite the server being drained
      response = Task.await(request_task, 5_000)
      assert response.status == 200
      assert response.body == "ok"

      # Now the drain/stop should finish
      assert :ok = Task.await(stop_task, 5_000)
    end)
  end

  test "new connections are refused after drainer begins shutdown" do
    {server_pid, port} = start_server!(SlowPlug)
    _drainer = start_drainer!(server_pid)

    with_bandit_mock(server_pid, fn ->
      GenServer.stop(:test_drainer, :normal, 10_000)
    end)

    # Server is suspended — new connections should be refused
    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Req.get("http://127.0.0.1:#{port}/", retry: false)
  end

  test "completes immediately when there are no active connections" do
    {server_pid, _port} = start_server!(SlowPlug)
    _drainer = start_drainer!(server_pid)

    with_bandit_mock(server_pid, fn ->
      # Should return near-instantly since no connections are active
      {elapsed, :ok} =
        :timer.tc(fn -> GenServer.stop(:test_drainer, :normal, 10_000) end, :millisecond)

      assert elapsed < 500
    end)
  end
end
