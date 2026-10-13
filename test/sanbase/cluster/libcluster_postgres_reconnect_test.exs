defmodule Sanbase.Cluster.LibclusterPostgresReconnectTest do
  # Simulates Postgres closing the LISTEN connection
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
    assert :ok = wait_until(fn -> backend_count(context.app_name) >= 2 end)

    terminated_pids = terminate_backends(context.app_name)
    assert length(terminated_pids) >= 2

    # The LISTEN connection reconnects (new backend) and subscribes to the channel again
    assert :ok = wait_until(fn -> listen_backend?(context.app_name, terminated_pids) end)

    refute_received {:DOWN, ^ref, :process, ^pid, _reason}
    assert Process.alive?(pid)
  end

  defp backend_count(app_name) do
    %{rows: [[count]]} =
      stat_query("SELECT count(*) FROM pg_stat_activity WHERE application_name = $1", [app_name])

    count
  end

  defp listen_backend?(app_name, terminated_pids) do
    %{rows: [[count]]} =
      stat_query(
        """
        SELECT count(*) FROM pg_stat_activity
        WHERE application_name = $1 AND query LIKE '%LISTEN%' AND pid <> ALL($2)
        """,
        [app_name, terminated_pids]
      )

    count > 0
  end

  defp terminate_backends(app_name) do
    %{rows: rows} =
      stat_query(
        "SELECT pid, pg_terminate_backend(pid) FROM pg_stat_activity WHERE application_name = $1",
        [app_name]
      )

    Enum.map(rows, fn [pid, _terminated] -> pid end)
  end

  # pg_stat_activity is snapshotted once per (sandbox) transaction, so clear it before each read
  defp stat_query(sql, params) do
    Sanbase.Repo.query!("SELECT pg_stat_clear_snapshot()")
    Sanbase.Repo.query!(sql, params)
  end

  defp wait_until(fun), do: Sanbase.ClusterCase.wait_until(fun, 10_000, 100)
end
