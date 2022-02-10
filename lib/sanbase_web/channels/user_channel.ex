defmodule SanbaseWeb.UserChannel do
  use SanbaseWeb, :channel

  alias SanbaseWeb.Presence
  alias Sanbase.Accounts.User

  def join("users:" <> user_id, _params, socket) do
    case String.to_integer(user_id) == socket.assigns.user_id do
      true ->
        {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
        {:ok, socket}

      false ->
        {:error, "Cannot join other users rooms"}
    end
  end

  def handle_in("is_username_valid", %{"username" => username}, socket) do
    case User.Username.valid?(username) do
      true ->
        {:reply, {:ok, %{"is_username_valid" => true}}, socket}

      {:error, reason} ->
        {:reply, {:ok, %{"is_username_valid" => false, "reason" => reason}}, socket}
    end
  end

  def handle_in("open_tabs", %{}, socket) do
    user_id = "#{socket.assigns.user_id}"

    case Presence.list(socket) do
      %{^user_id => %{metas: list}} ->
        {:reply, {:ok, %{"open_tabs" => length(list)}}, socket}

      %{} = empty_map when map_size(empty_map) == 0 ->
        {:reply, {:ok, %{"open_tabs" => 0}}, socket}
    end
  end
end
