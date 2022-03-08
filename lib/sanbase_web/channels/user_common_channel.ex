defmodule SanbaseWeb.UserCommonChannel do
  use SanbaseWeb, :channel

  def join("users:common", _params, socket) do
    {:ok, socket}
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
end
