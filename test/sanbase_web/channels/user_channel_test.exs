defmodule SanbaseWeb.UserChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user, username: "my_user")
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)

    %{user: user, conn: conn}
  end

  test "test can open multiple websockets and join room", context do
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

  test "test open_tabs message", context do
    for i <- 1..5 do
      socket = get_socket(context)

      ref = push(socket, "open_tabs", %{})
      assert_reply(ref, :ok, %{"open_tabs" => ^i})
    end
  end

  test "test username validation", context do
    socket = get_socket(context)

    ref = push(socket, "is_username_valid", %{"username" => nil})

    assert_reply(ref, :ok, %{
      "is_username_valid" => false,
      "reason" => "Username must be a string and not null"
    })

    ref = push(socket, "is_username_valid", %{"username" => "my"})

    assert_reply(ref, :ok, %{
      "is_username_valid" => false,
      "reason" => "Username must be at least 4 characters long"
    })

    ref = push(socket, "is_username_valid", %{"username" => context.user.username})
    assert_reply(ref, :ok, %{"is_username_valid" => false, "reason" => "Username is taken"})
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
