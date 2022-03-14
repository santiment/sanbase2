defmodule SanbaseWeb.UserChannel do
  use SanbaseWeb, :channel

  def join("users:common", _params, socket) do
    {:ok, socket}
  end

  def join("users:" <> user_id, _params, socket) do
    case String.to_integer(user_id) == socket.assigns.user_id do
      true ->
        {:ok, assign(socket, :user_joined_own_channel, true)}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("users_by_username_pattern", %{"username_pattern" => username_pattern}, socket) do
    user_maps = Sanbase.Accounts.Search.by_username(username_pattern)
    response = %{"users" => user_maps}
    {:reply, {:ok, response}, socket}
  end

  def handle_in("is_username_valid", %{"username" => username}, socket) do
    case Sanbase.Accounts.User.Name.valid_username?(username) do
      true ->
        {:reply, {:ok, %{"is_username_valid" => true}}, socket}

      {:error, reason} ->
        {:reply, {:ok, %{"is_username_valid" => false, "reason" => reason}}, socket}
    end
  end

  defguard is_own_channel(socket)
           when is_map_key(socket, :assigns) and
                  is_map_key(socket.assigns, :user_joined_own_channel) and
                  socket.assigns.user_joined_own_channel == true

  def handle_in("my_username", _params, socket) when is_own_channel(socket) do
    # A dummy message that is used to test the proper dispatching of
    # channels between users:common and users:<user_id>. Not used.
    {:reply, {:ok, socket.assigns.user.username}, socket}
  end
end
