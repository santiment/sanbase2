defmodule SanbaseWeb.UserActivityChannel do
  use SanbaseWeb, :channel

  def join("user_activities:" <> user_id, _params, socket) do
    case String.to_integer(user_id) == socket.assigns.user_id do
      true ->
        {:ok, socket}

      false ->
        {:error, "The channel subtopic must be the authenticated user id"}
    end
  end

  def handle_in(
        "store_user_activity",
        %{
          "entity_id" => entity_id,
          "entity_type" => entity_type,
          "activity_type" => activity_type
        } = params,
        socket
      ) do
    entity_details = Map.get(params, "entity_details", %{})

    data = %{
      entity_id: entity_id,
      entity_type: entity_type,
      activity_type: activity_type,
      entity_details: entity_details
    }

    Sanbase.Accounts.Activity.store_user_activity(socket.assigns.user_id, data)

    {:noreply, socket}
  end
end
