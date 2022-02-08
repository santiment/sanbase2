defmodule SanbaseWeb.UserChannel do
  use SanbaseWeb, :channel

  alias SanbaseWeb.Presence

  def join("users:" <> _user_id, _params, socket) do
    {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
    {:ok, socket}
  end

  def handle_in("is_username_valid", %{"username" => username}, socket) do
    case Sanbase.Accounts.User.Username.valid?(username) do
      true ->
        {:reply, {:ok, %{"is_username_valid" => true}}, socket}

      {:error, reason} ->
        {:reply, {:ok, %{"is_username_valid" => false, "reason" => reason}}, socket}
    end
  end

  def handle_in("tabs_open", %{}, socket) do
    user_id = "#{socket.assigns.user_id}"

    case Presence.list(socket) do
      %{^user_id => %{metas: list}} ->
        {:reply, {:ok, %{"tabs_open" => length(list)}}, socket}

      %{} = empty_map when map_size(empty_map) == 0 ->
        {:reply, {:ok, %{"tabs_open" => 0}}, socket}
    end
  end
end
