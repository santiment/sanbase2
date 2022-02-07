defmodule SanbaseWeb.UserChannel do
  use SanbaseWeb, :channel

  alias SanbaseWeb.Presence

  def join("users:online", _params, socket) do
    case Presence.list(socket) do
      %{} = empty_map when map_size(empty_map) == 0 ->
        {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
        {:ok, socket}

      _ ->
        {:error, %{reason: "Only one websocket per user is allowed"}}
    end
  end

  def join("users:" <> private_room_id, _params, _socket) do
    {:error, %{reason: "unauthorized"}}
  end
end
