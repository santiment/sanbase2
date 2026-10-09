defmodule Sanbase.Cluster.LibclusterPostgresReconnectTest do
  # Reproduces Sentry SANBASE-BACKEND-PROD-G61 + SANBASE-BACKEND-PROD-GA8:
  #   DBConnection.ConnectionError: ssl async_recv: closed
  #   G61 - crash report from gen_statem.erl (the Postgrex.Notifications /
  #         Postgrex.SimpleConnection process)
  #   GA8 - crash report from gen_server.erl, same millisecond, same pod
  #         (the linked LibclusterPostgres.Strategy GenServer)
  #
  # Only the pods that start libcluster (web, admin, signals/alerts) report it,
  # always ~06:xx UTC - i.e. when Postgres closes connections (maintenance).
  #
  # LibclusterPostgres.Strategy (libcluster_postgres 0.2.0) starts
  # `Postgrex.Notifications.start_link/1` without `auto_reconnect: true` and
  # does not trap exits, so when the server closes the LISTEN connection the
  # notifications process stops with the ConnectionError and takes the
  # strategy GenServer down with it.
  #
  # Sanbase.Cluster.PostgresStrategy wraps that strategy and starts the LISTEN
  # connection with `auto_reconnect: true`.
  #
  # The test runs the strategy against the LOCAL test database,
  # terminates its backends with pg_terminate_backend (simulating the server
  # closing the connection) and asserts the strategy survives. Locally the
  # exit reason is `Postgrex.Error (admin_shutdown)` rather than
  # "ssl async_recv: closed" (pg_terminate_backend sends a FATAL before closing
  # the socket), but the crash path - SimpleConnection stops because
  # auto_reconnect is false, linked strategy exits - is the same.
  use Sanbase.DataCase, async: false

  @moduletag capture_log: true

  setup do
    repo_config = Sanbase.Repo.config()
    hostname = Keyword.get(repo_config, :hostname, "localhost")

    # Safety net: this test must only ever touch a local database.
    assert hostname in ["localhost", "127.0.0.1"]

    app_name = "sanbase_libcluster_test_#{System.unique_integer([:positive])}"

    config = [
      hostname: hostname,
      username: Keyword.get(repo_config, :username),
      password: Keyword.get(repo_config, :password),
      database: Keyword.fetch!(repo_config, :database),
      port: Keyword.get(repo_config, :port, 5432),
      parameters: [application_name: app_name],
      ssl: false,
      channel_name: app_name,
      heartbeat_interval: 60_000
    ]

    %{config: config, app_name: app_name}
  end

  test "the libcluster Postgres strategy survives the server closing its connections",
       context do
    state = %Cluster.Strategy.State{
      topology: :sanbase_libcluster_reconnect_test,
      connect: {:net_kernel, :connect_node, []},
      disconnect: {:erlang, :disconnect_node, []},
      list_nodes: {:erlang, :nodes, [:connected]},
      config: context.config
    }

    pid =
      start_supervised!(%{
        id: Sanbase.Cluster.PostgresStrategy,
        start: {Sanbase.Cluster.PostgresStrategy, :start_link, [[state]]},
        restart: :temporary
      })

    ref = Process.monitor(pid)

    # Wait for both the query connection and the LISTEN connection to be up
    assert wait_until(fn -> backend_count(context.app_name) >= 2 end)

    terminated_pids = terminate_backends(context.app_name)
    assert length(terminated_pids) >= 2

    refute_receive {:DOWN, ^ref, :process, ^pid, _reason}, 1_000
    assert Process.alive?(pid)

    # The LISTEN connection reconnects (new backend) and subscribes to the channel again
    assert wait_until(fn -> listen_backend?(context.app_name, terminated_pids) end)
  end

  # The test runs inside the SQL sandbox transaction, and pg_stat_activity is
  # snapshotted once per transaction, so clear the snapshot before each read.
  defp backend_count(app_name) do
    Sanbase.Repo.query!("SELECT pg_stat_clear_snapshot()")

    %{rows: [[count]]} =
      Sanbase.Repo.query!(
        "SELECT count(*) FROM pg_stat_activity WHERE application_name = $1",
        [app_name]
      )

    count
  end

  defp listen_backend?(app_name, terminated_pids) do
    Sanbase.Repo.query!("SELECT pg_stat_clear_snapshot()")

    %{rows: [[count]]} =
      Sanbase.Repo.query!(
        """
        SELECT count(*) FROM pg_stat_activity
        WHERE application_name = $1 AND query LIKE '%LISTEN%' AND pid <> ALL($2)
        """,
        [app_name, terminated_pids]
      )

    count > 0
  end

  defp terminate_backends(app_name) do
    Sanbase.Repo.query!("SELECT pg_stat_clear_snapshot()")

    %{rows: rows} =
      Sanbase.Repo.query!(
        "SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1",
        [app_name]
      )

    Enum.map(rows, fn [pid, _terminated] -> pid end)
  end

  defp wait_until(fun, attempts \\ 50)
  defp wait_until(_fun, 0), do: false

  defp wait_until(fun, attempts) do
    if fun.() do
      true
    else
      Process.sleep(100)
      wait_until(fun, attempts - 1)
    end
  end
end
