defmodule SanbaseWeb.NotificationsChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup_all do
    # The GenServer is already running (started by supervision tree)
    # but not subscribed to EventBus (disabled in test.exs config).
    # We only need to subscribe it to EventBus topics.
    subscriber = Sanbase.EventBus.AppNotificationsSubscriber
    EventBus.subscribe({subscriber, subscriber.topics()})

    on_exit(fn ->
      Sanbase.EventBus.drain_topics(subscriber.topics(), 10_000)
      EventBus.unsubscribe(subscriber)
    end)
  end

  setup do
    user = insert(:user, username: "my_user")
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)

    %{user: user, conn: conn}
  end

  test "test join channel with user id", context do
    {:ok, socket} =
      connect(
        SanbaseWeb.UserSocket,
        %{"access_token" => context.conn.private.plug_session["access_token"]}
      )

    assert {:ok, %{}, %Phoenix.Socket{} = _socket} =
             subscribe_and_join(
               socket,
               SanbaseWeb.NotificationsChannel,
               "notifications:#{context.user.id}",
               %{}
             )
  end

  test "use receives notifications via websocket", %{user: user} = context do
    # joins the notifications:#{user_id} channel
    _socket = get_socket(context)

    user2 = insert(:user, username: "another_user")

    assert {:ok, _} = Sanbase.Accounts.UserFollower.follow(user2.id, user.id)

    # This insert will create a notification for user as user2 is followed by user
    assert {:ok, _} =
             Sanbase.UserList.create_user_list(user2, %{is_public: true, name: "my list"})

    # This insert will NOT create a notification for user2 as user is not followed by user2
    assert {:ok, _} = Sanbase.UserList.create_user_list(user, %{is_public: true, name: "my list"})

    user_id = user.id
    user2_id = user2.id
    assert_push("notification", %{user_id: ^user_id, notification_id: _notification_id})
    refute_push("notification", %{user_id: ^user2_id, notification_id: _notification_id})
  end

  defp get_socket(context) do
    {:ok, socket} =
      connect(
        SanbaseWeb.UserSocket,
        %{
          "access_token" => context.conn.private.plug_session["access_token"]
        }
      )

    {:ok, _, socket} =
      subscribe_and_join(
        socket,
        SanbaseWeb.NotificationsChannel,
        "notifications:#{context.user.id}",
        %{}
      )

    socket
  end
end
