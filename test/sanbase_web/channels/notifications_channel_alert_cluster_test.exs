defmodule SanbaseWeb.NotificationsChannelAlertClusterTest do
  @moduledoc """
  End-to-end distributed test for alert-fired → websocket broadcast.

  Role inversion compared to `NotificationsChannelClusterTest`:
  - The **primary** test node plays the `signals`/`alerts` pod: it fires
    the alert via `Sanbase.EventBus`, and the `AppNotificationsSubscriber`
    running on it (enabled in `setup_all`) writes DB rows (inside the
    ChannelCase sandbox) and calls `SanbaseWeb.Endpoint.broadcast/3`.
  - The **peer** plays the `web` pod by booting the real `web` application
    path. A small forwarder process subscribes to the user's notification
    topic on that node and relays everything back to the test process.

  We still keep the DB work on the primary, so the test stays reasonably cheap
  while covering a real remote application boot.

  Skipped by default. Run with:

      mix test --include distributed \\
        test/sanbase_web/channels/notifications_channel_alert_cluster_test.exs
  """

  use SanbaseWeb.ChannelCase

  import Sanbase.Factory

  alias Sanbase.ClusterCase

  @moduletag :distributed

  setup_all do
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber
    Sanbase.EventBus.subscribe_subscriber(subscriber)

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      Sanbase.EventBus.unsubscribe_subscriber(subscriber)
    end)

    {peer, node} = ClusterCase.start_peer!(:web, mode: {:sanbase, "web"})

    on_exit(fn ->
      ClusterCase.stop_peer(peer)
    end)

    %{peer_node: node}
  end

  test "firing an alert on primary (alerts pod) delivers the broadcast on peer (web pod)",
       %{peer_node: node} do
    user = insert(:user, username: "alerts_pod_user")
    topic = "notifications:#{user.id}"
    test_pid = self()
    ref = make_ref()

    # Spawn a forwarder on the peer. It subscribes to the PubSub topic
    # locally on the peer and relays every received message back to us.
    _receiver =
      :erpc.call(node, :erlang, :spawn, [
        Sanbase.ClusterCase,
        :subscribe_and_forward,
        [Sanbase.PubSub, topic, test_pid, ref]
      ])

    # Wait until the forwarder has actually subscribed on the peer
    # (otherwise a broadcast could arrive before the subscription exists).
    assert_receive {^ref, :subscribed}, 1_000

    # Prove the primary -> peer path with a probe message before firing the
    # real alert event. Retry until PubSub cluster convergence delivers the
    # probe so the test does not flake on a slow first broadcast.
    probe_ref = make_ref()

    ClusterCase.wait_until!(
      fn ->
        :ok = SanbaseWeb.Endpoint.broadcast(topic, "cluster_probe", %{ref: probe_ref})

        receive do
          {^ref,
           %Phoenix.Socket.Broadcast{
             topic: ^topic,
             event: "cluster_probe",
             payload: %{ref: ^probe_ref}
           }} ->
            true
        after
          50 -> false
        end
      end,
      "Timed out waiting for primary -> peer probe delivery on #{node}"
    )

    # Fire the alert on the primary. This triggers the real subscriber
    # pipeline: DB insert → async broadcast → distributed PubSub → peer.
    Sanbase.EventBus.notify(%{
      topic: :alert_events,
      data: %{
        event_type: :alert_triggered,
        user_id: user.id,
        alert_id: 999_000,
        alert_title: "Test alert",
        alert_description: "Triggered from alerts pod",
        alert_is_active: true
      }
    })

    user_id = user.id

    assert_receive {^ref,
                    %Phoenix.Socket.Broadcast{
                      topic: ^topic,
                      event: "notification",
                      payload: %{user_id: ^user_id, notification_id: _}
                    }},
                   3_000
  end
end
