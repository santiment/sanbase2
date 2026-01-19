defmodule SanbaseWeb.NotificationsChannel do
  use SanbaseWeb, :channel

  def join("notifications:" <> user_id, _params, socket) do
    case Integer.parse(user_id) do
      {user_id, ""} when is_integer(user_id) ->
        {:ok, socket}

      res ->
        {:error, "The channel subtopic must be the authenticated user id. res: #{inspect(res)}"}
    end
  end
end
