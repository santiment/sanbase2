defmodule SanbaseWeb.UserChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  setup do
    user = insert(:user, username: "my_user")
    conn = setup_jwt_auth(Phoenix.ConnTest.build_conn(), user)

    %{user: user, conn: conn}
  end

  describe "join common channel" do
    test "test join channel" do
      assert {:ok, socket} = connect(SanbaseWeb.UserSocket, %{}, %{})

      assert {:ok, %{}, %Phoenix.Socket{}} =
               subscribe_and_join(
                 socket,
                 SanbaseWeb.UserChannel,
                 "users:common",
                 %{}
               )
    end

    test "get users by username pattern" do
      u1 = insert(:user, username: "test2")
      u2 = insert(:user, username: "test")
      u3 = insert(:user, username: "my_test2")
      _ = insert(:user, username: "somethingelse")
      socket = get_socket()

      ref = push(socket, "users_by_username_pattern", %{"username_pattern" => "test"})
      assert_reply(ref, :ok, %{"users" => users})

      assert users |> Enum.map(& &1.username) ==
               [
                 u2.username,
                 u1.username,
                 u3.username
               ]
    end

    test "test username validation" do
      socket = get_socket()

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

      # Create a random username that has both upper and lower case letters
      # Provide the same username all lowercased in the request
      user = insert(:user, username: rand_hex_str(10) <> "1_aAa")
      ref = push(socket, "is_username_valid", %{"username" => String.downcase(user.username)})

      assert_reply(ref, :ok, %{
        "is_username_valid" => false,
        "reason" => "Username is taken"
      })
    end

    defp get_socket() do
      {:ok, socket} = connect(SanbaseWeb.UserSocket, %{}, %{})

      {:ok, _, socket} = subscribe_and_join(socket, SanbaseWeb.UserChannel, "users:common", %{})

      socket
    end
  end

  describe "join channel with user id" do
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
end
