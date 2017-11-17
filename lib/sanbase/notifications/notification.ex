defmodule Sanbase.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.Type
  alias Sanbase.Notifications.Notification
  alias Sanbase.Model.Project

  schema "notification" do
    belongs_to :project, Project
    belongs_to :type, Type

    timestamps()
  end

  def changeset(%Notification{} = notification, attrs \\ %{}) do
    notification
    |> cast(attrs, [:project_id, :type_id])
    |> validate_required([:project_id, :type_id])
  end
end
