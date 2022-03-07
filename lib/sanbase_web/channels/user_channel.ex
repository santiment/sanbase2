defmodule SanbaseWeb.UserChannel do
  use SanbaseWeb, :channel

  def join("users:" <> user_id, _params, socket) do
    case String.to_integer(user_id) == socket.assigns.user_id do
      true ->
        {:ok, socket}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("my_username", _params, socket) do
    # A dummy message that is used to test the proper dispatching of
    # channels between users:common and users:<user_id>. Not used.
    {:reply, {:ok, socket.assigns.user.username}, socket}
  end
end
