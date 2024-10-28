defmodule Sanbase.Notifications.NotificationAction do
  use Ecto.Schema
  import Ecto.Changeset

  schema "notification_actions" do
    field(:status, NotificationStatusEnum)
    field(:action_type, NotificationActionTypeEnum)
    field(:scheduled_at, :utc_datetime)
    field(:requires_verification, :boolean, default: false)
    field(:verified, :boolean, default: false)

    has_many(:notifications, Sanbase.Notifications.Notification)

    timestamps()
  end

  @doc false
  def changeset(notification_action, attrs) do
    notification_action
    |> cast(attrs, [:action_type, :scheduled_at, :status, :requires_verification, :verified])
    |> validate_required([:action_type, :scheduled_at, :status, :requires_verification, :verified])
    |> validate_status()
    |> validate_action_type()
  end

  defp validate_status(changeset) do
    validate_change(changeset, :status, fn _, status ->
      if NotificationStatusEnum.valid_value?(status) do
        []
      else
        [status: "is invalid"]
      end
    end)
  end

  defp validate_action_type(changeset) do
    validate_change(changeset, :action_type, fn _, action_type ->
      if NotificationActionTypeEnum.valid_value?(action_type) do
        []
      else
        [action_type: "is invalid"]
      end
    end)
  end
end
