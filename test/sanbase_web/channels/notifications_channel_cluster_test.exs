defmodule SanbaseWeb.NotificationsChannelClusterTest do
  @moduledoc """
  Cross-node test proving that a broadcast originated on a peer BEAM node
  running the real `signals`/`alerts` application path reaches a channel
  subscriber on the primary node (simulating the `web` pod) through
  distributed `Phoenix.PubSub`.

  Tagged `:distributed` so it can be opted out of a fast local run via
  `mix test --exclude distributed`. It otherwise runs as part of the normal
  suite in CI.
  """

  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.ClusterCase

  @moduletag :distributed

  setup_all do
    {peer, node} = ClusterCase.start_peer!(:alerts, mode: {:sanbase, "signals"})
    on_exit(fn -> ClusterCase.stop_peer(peer) end)
    %{peer_node: node}
  end

  setup do
    user = insert(:user, username: "cluster_user")
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)
    %{user: user, conn: conn}
  end

  test "broadcast from peer (alerts) node reaches channel on primary (web) node",
       %{user: user, conn: conn, peer_node: node} do
    topic = "notifications:#{user.id}"

    {:ok, socket} =
      connect(SanbaseWeb.UserSocket, %{
        "access_token" => conn.private.plug_session["access_token"]
      })

    {:ok, _, _socket} =
      subscribe_and_join(socket, SanbaseWeb.NotificationsChannel, topic, %{})

    # Prove the cross-node PubSub path with a small probe before asserting on
    # the channel push. This waits on public behavior instead of PubSub internals.
    probe_topic = "cluster_probe:#{user.id}:#{System.unique_integer([:positive])}"
    probe_ref = make_ref()

    :ok = Phoenix.PubSub.subscribe(Sanbase.PubSub, probe_topic)

    ClusterCase.wait_until!(
      fn ->
        :ok =
          :erpc.call(node, SanbaseWeb.Endpoint, :broadcast, [
            probe_topic,
            "cluster_probe",
            %{ref: probe_ref}
          ])

        receive do
          %Phoenix.Socket.Broadcast{
            topic: ^probe_topic,
            event: "cluster_probe",
            payload: %{ref: ^probe_ref}
          } ->
            true
        after
          50 -> false
        end
      end,
      "Timed out waiting for cross-node probe delivery from #{node}"
    )

    :ok = Phoenix.PubSub.unsubscribe(Sanbase.PubSub, probe_topic)

    # Use the same high-level broadcast API the alerts pod uses in production.
    :ok =
      :erpc.call(node, SanbaseWeb.Endpoint, :broadcast, [
        topic,
        "notification",
        %{user_id: user.id, notification_id: 4242}
      ])

    user_id = user.id

    assert_push(
      "notification",
      %{user_id: ^user_id, notification_id: 4242},
      2_000
    )
  end
end
