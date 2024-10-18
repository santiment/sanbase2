defmodule Sanbase.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.NotificationAction

  schema "notifications" do
    field(:status, NotificationStatusEnum)
    field(:step, NotificationStepEnum)
    field(:channels, {:array, NotificationChannelEnum})
    field(:scheduled_at, :utc_datetime)
    field(:sent_at, :utc_datetime)
    field(:content, :string)
    field(:display_in_ui, :boolean, default: false)
    field(:template_params, :map)

    belongs_to(:notification_action, NotificationAction)

    timestamps()
  end

  @doc false
  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :step,
      :status,
      :scheduled_at,
      :sent_at,
      :channels,
      :content,
      :display_in_ui,
      :template_params
    ])
    |> validate_required([
      :step,
      :status,
      :scheduled_at,
      :sent_at,
      :channels,
      :content,
      :display_in_ui
    ])
    |> validate_status()
    |> validate_step()
    |> validate_channels()
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

  defp validate_step(changeset) do
    validate_change(changeset, :step, fn _, step ->
      if NotificationStepEnum.valid_value?(step) do
        []
      else
        [step: "is invalid"]
      end
    end)
  end

  defp validate_channels(changeset) do
    validate_change(changeset, :channels, fn _, channels ->
      if is_list(channels) and Enum.all?(channels, &NotificationChannelEnum.valid_value?/1) do
        []
      else
        [channels: "contains invalid values"]
      end
    end)
  end
end
