defmodule SanbaseWeb.UserCommonChannelTest do
  use SanbaseWeb.ChannelCase

  import Sanbase.Factory

  test "test join channel" do
    assert {:ok, socket} = connect(SanbaseWeb.UserSocket, %{}, %{})

    assert {:ok, %{}, %Phoenix.Socket{}} =
             subscribe_and_join(
               socket,
               SanbaseWeb.UserCommonChannel,
               "users:common",
               %{}
             )
  end

  describe "fetch users by username pattern" do
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

    {:ok, _, socket} =
      subscribe_and_join(socket, SanbaseWeb.UserCommonChannel, "users:common", %{})

    socket
  end
end
