defmodule SanbaseWeb.ConnectionDrainingTest do
  @moduledoc """
  Verify that Bandit/ThousandIsland's built-in connection draining works:
  when the server shuts down, in-flight requests complete gracefully
  and new connections are refused.

  Cowboy does not have connection draining — on deploy, all connections
  are terminated immediately. Bandit/ThousandIsland handles this natively
  via the shutdown_timeout option (see runtime.exs).
  """
  use ExUnit.Case, async: true

  defmodule SlowPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      Process.sleep(1_000)

      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "ok")
    end
  end

  defmodule FastPlug do
    @moduledoc false
    import Plug.Conn

    def init(opts), do: opts

    def call(conn, _opts) do
      conn
      |> put_resp_content_type("text/plain")
      |> send_resp(200, "ok")
    end
  end

  defp start_server!(plug, opts \\ []) do
    shutdown_timeout = Keyword.get(opts, :shutdown_timeout, 15_000)

    bandit_opts = [
      plug: plug,
      port: 0,
      startup_log: false,
      thousand_island_options: [shutdown_timeout: shutdown_timeout]
    ]

    # Start Bandit under its own supervisor so we can stop it directly,
    # simulating what happens during a real application shutdown.
    {:ok, sup} = Supervisor.start_link([{Bandit, bandit_opts}], strategy: :one_for_one)
    [{_id, server_pid, _type, _modules}] = Supervisor.which_children(sup)
    {:ok, {_ip, port}} = ThousandIsland.listener_info(server_pid)

    {sup, server_pid, port}
  end

  test "in-flight requests complete before shutdown finishes" do
    {sup, _server_pid, port} = start_server!(SlowPlug)
    test_pid = self()

    # Start a slow request in a separate process
    request_task =
      Task.async(fn ->
        send(test_pid, :request_started)
        Req.get!("http://127.0.0.1:#{port}/")
      end)

    assert_receive :request_started, 1_000
    # Let Bandit accept the connection before initiating shutdown
    Process.sleep(100)

    # Stop the supervisor — simulates application shutdown.
    # This should block until connections drain.
    stop_task = Task.async(fn -> Supervisor.stop(sup, :normal) end)

    # The stop should NOT return instantly because the request is still in-flight
    refute Task.yield(stop_task, 200)

    # The in-flight request should complete successfully despite shutdown
    response = Task.await(request_task, 5_000)
    assert response.status == 200
    assert response.body == "ok"

    # Now shutdown should finish
    assert :ok = Task.await(stop_task, 5_000)
  end

  test "new connections are refused after shutdown begins" do
    {sup, _server_pid, port} = start_server!(SlowPlug)
    test_pid = self()

    # Start a slow request to keep the server draining
    _request_task =
      Task.async(fn ->
        send(test_pid, :request_started)
        Req.get("http://127.0.0.1:#{port}/")
      end)

    assert_receive :request_started, 1_000
    Process.sleep(100)

    # Begin shutdown in background — server is now draining
    _stop_task = Task.async(fn -> Supervisor.stop(sup, :normal) end)

    # Give ThousandIsland a moment to close the listening socket
    Process.sleep(100)

    # New connections should be refused
    assert {:error, %Req.TransportError{reason: :econnrefused}} =
             Req.get("http://127.0.0.1:#{port}/", retry: false)
  end

  test "shutdown completes immediately when there are no active connections" do
    {sup, _server_pid, _port} = start_server!(FastPlug)

    {elapsed, :ok} =
      :timer.tc(fn -> Supervisor.stop(sup, :normal) end, :millisecond)

    assert elapsed < 500
  end

  test "connections are forcibly terminated after shutdown_timeout expires" do
    # Use a very short shutdown_timeout so the test doesn't take forever.
    # The SlowPlug takes 1s, but we only allow 200ms for draining.
    {sup, _server_pid, port} = start_server!(SlowPlug, shutdown_timeout: 200)

    # Start a request that will take longer than the shutdown_timeout
    request_task =
      Task.async(fn ->
        Req.get("http://127.0.0.1:#{port}/", retry: false)
      end)

    Process.sleep(100)

    # Shutdown — should forcibly kill after ~200ms, not wait the full 1s
    {elapsed, :ok} =
      :timer.tc(fn -> Supervisor.stop(sup, :normal) end, :millisecond)

    # Should complete well under the 1s request duration
    assert elapsed < 1_000

    # The request should have been terminated (connection reset/closed)
    assert {:error, _} = Task.await(request_task, 2_000)
  end
end
