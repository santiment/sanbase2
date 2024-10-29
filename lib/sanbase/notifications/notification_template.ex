defmodule Sanbase.Notifications.NotificationTemplate do
  use Ecto.Schema
  import Ecto.Changeset

  @channels ["email", "telegram", "discord", "all"]

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
    |> validate_inclusion(:channel, @channels)
    |> unique_constraint([:action_type, :step, :channel],
      message: "template already exists for this action_type/step/channel combination"
    )
  end
end
