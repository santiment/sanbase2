defmodule SanbaseWeb.NotificationsChannel do
  use SanbaseWeb, :channel

  # Anonymous sockets have `user_id: nil`, so this rejects them too.
  def join("notifications:" <> subtopic, _params, socket) do
    case Integer.parse(subtopic) do
      {user_id, ""} when user_id == socket.assigns.user_id ->
        {:ok, socket}

      _ ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end
end
