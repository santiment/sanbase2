defmodule SanbaseWeb.UserChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user)
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)

    %{user: user, conn: conn}
  end

  test "test", context do
    assert {:ok, socket} =
             connect(
               SanbaseWeb.UserSocket,
               %{
                 "access_token" => context.conn.private.plug_session["access_token"],
                 "user_id" => context.user.id
               },
               %{}
             )

    assert {:ok, _, _socket} =
             subscribe_and_join(socket, SanbaseWeb.UserChannel, "users:online", %{})

    for _ <- 1..10 do
      assert {:ok, socket} =
               connect(
                 SanbaseWeb.UserSocket,
                 %{
                   "access_token" => context.conn.private.plug_session["access_token"],
                   "user_id" => context.user.id
                 },
                 %{}
               )

      assert {:error, _reason} =
               subscribe_and_join(socket, SanbaseWeb.UserChannel, "users:online", %{})
    end
  end
end
