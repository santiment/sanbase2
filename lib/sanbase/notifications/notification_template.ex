defmodule Sanbase.Notifications.NotificationTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.Notification

  @supported_channels Notification.supported_channels() ++ ["all"]
  @supported_actions Notification.supported_actions()
  @supported_steps Notification.supported_steps()

  schema "notification_templates" do
    field(:channel, :string)
    field(:action_type, :string)
    field(:step, :string)
    field(:template, :string)

    timestamps()
  end

  @doc false
  def changeset(notification_template, attrs) do
    notification_template
    |> cast(attrs, [:channel, :action_type, :step, :template])
    |> validate_required([:channel, :action_type, :template])
    |> validate_inclusion(:channel, @supported_channels)
    |> validate_inclusion(:action_type, @supported_actions)
    |> validate_inclusion(:step, @supported_steps)
    |> unique_constraint([:action_type, :step, :channel],
      message: "template already exists for this action_type/step/channel combination"
    )
  end
end
