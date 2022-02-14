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

  def handle_in("is_username_valid", %{"username" => username}, socket) do
    case Sanbase.Accounts.User.Name.valid_username?(username) do
      true ->
        {:reply, {:ok, %{"is_username_valid" => true}}, socket}

      {:error, reason} ->
        {:reply, {:ok, %{"is_username_valid" => false, "reason" => reason}}, socket}
    end
  end
end
