defmodule SanbaseWeb.OpenTabChannelTest do
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
             subscribe_and_join(
               socket,
               SanbaseWeb.OpenRestrictedTabChannel,
               "open_restricted_tabs:#{context.user.id}",
               %{}
             )
  end

  test "test open_restricted_tabs message", context do
    for i <- 1..5 do
      socket = get_socket(context)

      ref = push(socket, "open_restricted_tabs", %{})
      assert_reply(ref, :ok, %{"open_restricted_tabs" => ^i})
    end
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
      subscribe_and_join(
        socket,
        SanbaseWeb.OpenRestrictedTabChannel,
        "open_restricted_tabs:#{context.user.id}",
        %{}
      )

    socket
  end
end
