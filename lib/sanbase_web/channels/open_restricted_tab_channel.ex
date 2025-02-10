defmodule SanbaseWeb.OpenRestrictedTabChannel do
  @moduledoc false
  use SanbaseWeb, :channel

  alias SanbaseWeb.Presence

  def join("open_restricted_tabs:" <> user_id, _params, socket) do
    if String.to_integer(user_id) == socket.assigns.user_id do
      {:ok, _} = Presence.track(socket, socket.assigns.user_id, %{})
      {:ok, socket}
    else
      {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in("open_restricted_tabs", %{}, socket) do
    user_id = "#{socket.assigns.user_id}"

    case Presence.list(socket) do
      %{^user_id => %{metas: list}} ->
        {:reply, {:ok, %{"open_restricted_tabs" => length(list)}}, socket}

      %{} = empty_map when map_size(empty_map) == 0 ->
        {:reply, {:ok, %{"open_restricted_tabs" => 0}}, socket}
    end
  end
end
