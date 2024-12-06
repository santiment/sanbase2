defmodule Sanbase.Notifications.NotificationTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Notifications.Notification

  @supported_channels Notification.supported_channels() ++ ["all"]
  @supported_actions Notification.supported_actions()
  @supported_steps Notification.supported_steps()
  @supported_mime_types ["text/plain", "text/html"]

  schema "notification_templates" do
    field(:channel, :string)
    field(:action, :string)
    field(:step, :string)
    field(:template, :string)
    field(:mime_type, :string)
    field(:required_params, {:array, :string})

    timestamps()
  end

  @doc false
  def changeset(notification_template, attrs) do
    notification_template
    |> cast(attrs, [:channel, :action, :step, :template, :mime_type, :required_params])
    |> validate_required([:channel, :action, :template])
    |> validate_inclusion(:channel, @supported_channels)
    |> validate_inclusion(:action, @supported_actions)
    |> validate_inclusion(:step, @supported_steps)
    |> validate_inclusion(:mime_type, @supported_mime_types)
    |> unique_constraint([:action, :step, :channel, :mime_type],
      message: "template already exists for this action/step/channel/mime_type combination"
    )
  end
end
