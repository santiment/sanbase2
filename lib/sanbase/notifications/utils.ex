defmodule Sanbase.Notifications.Utils do
  alias Sanbase.Repo
  alias Sanbase.Model.Project
  alias Sanbase.Notifications.Notification
  alias Sanbase.Notifications.Type

  import Ecto.Query

  def recent_notification?(project, cooldown_datetime, notification_type_name) do
    type = Repo.get_by(Type, name: notification_type_name)

    recent_notifications_count(project, type, cooldown_datetime) > 0
  end

  def insert_notification(project, notification_type_name) do
    type = get_or_create_notification_type(notification_type_name)

    %Notification{}
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:project, project)
    |> Ecto.Changeset.put_assoc(:type, type)
    |> Repo.insert!()
  end

  defp get_or_create_notification_type(notification_type_name) do
    Repo.get_by(Type, name: notification_type_name)
    |> case do
      result = %Type{} ->
        result
        |> Ecto.Changeset.change()

      nil ->
        %Type{}
        |> Type.changeset(%{name: notification_type_name})
    end
  end

  defp recent_notifications_count(_project, nil, _cooldown_datetime), do: 0

  defp recent_notifications_count(%Project{id: project_id}, %Type{id: type_id}, cooldown_datetime) do
    Notification
    |> where([n], project_id: ^project_id, type_id: ^type_id)
    |> where([n], n.inserted_at > ^cooldown_datetime)
    |> Repo.aggregate(:count, :id)
  end
end
