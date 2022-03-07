defmodule SanbaseWeb.UserChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user, username: "my_user")
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)

    %{user: user, conn: conn}
  end

  test "can join channel", context do
    assert {:ok, socket} =
             connect(
               SanbaseWeb.UserSocket,
               %{
                 "access_token" => context.conn.private.plug_session["access_token"]
               },
               %{}
             )

    assert {:ok, %{}, %Phoenix.Socket{}} =
             subscribe_and_join(socket, SanbaseWeb.UserChannel, "users:#{context.user.id}", %{})
  end

  test "test my_username", context do
    socket = get_socket(context)

    ref = push(socket, "my_username", %{})
    expected_username = context.user.username
    assert_reply(ref, :ok, ^expected_username)
  end

  defp get_socket(context) do
    {:ok, socket} =
      connect(
        SanbaseWeb.UserSocket,
        %{
          "access_token" => context.conn.private.plug_session["access_token"]
        },
        %{}
      )

    {:ok, _, socket} =
      subscribe_and_join(socket, SanbaseWeb.UserChannel, "users:#{context.user.id}", %{})

    socket
  end
end
