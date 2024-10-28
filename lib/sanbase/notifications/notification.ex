defmodule Sanbase.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.NotificationAction

  schema "notifications" do
    field(:status, NotificationStatusEnum, default: :pending)
    field(:step, NotificationStepEnum, default: :once)
    field(:channels, {:array, NotificationChannelEnum}, default: [])
    field(:scheduled_at, :utc_datetime)
    field(:sent_at, :utc_datetime)
    field(:content, :string)
    field(:display_in_ui, :boolean, default: false)
    field(:template_params, :map, default: %{})

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
      :template_params,
      :notification_action_id
    ])
    |> validate_required([
      :scheduled_at,
      :display_in_ui,
      :notification_action_id
    ])
    |> validate_inclusion(:status, NotificationStatusEnum.__enum_map__())
    |> validate_inclusion(:step, NotificationStepEnum.__enum_map__())
    |> validate_channels()
  end

  defp validate_channels(changeset) do
    if get_change(changeset, :channels) do
      validate_change(changeset, :channels, fn _, channels ->
        if is_list(channels) and Enum.all?(channels, &NotificationChannelEnum.valid_value?/1) do
          []
        else
          [channels: "contains invalid values"]
        end
      end)
    else
      changeset
    end
  end
end
