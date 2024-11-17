defmodule Sanbase.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo

  @supported_actions ["metric_created", "metric_updated", "metric_deleted", "manual", "alert"]
  @supported_channels ["discord", "email"]
  @supported_steps ["all", "before", "reminder", "after", "detected", "resolved"]

  def supported_channels, do: @supported_channels
  def supported_actions, do: @supported_actions
  def supported_steps, do: @supported_steps

  schema "notifications" do
    field(:action, :string)
    field(:params, :map)
    field(:channels, {:array, :string})
    field(:step, :string)
    field(:processed_for_discord, :boolean, default: false)
    field(:processed_for_discord_at, :utc_datetime)
    field(:processed_for_email, :boolean, default: false)
    field(:processed_for_email_at, :utc_datetime)

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :action,
      :params,
      :channels,
      :step,
      :processed_for_discord,
      :processed_for_discord_at,
      :processed_for_email,
      :processed_for_email_at
    ])
    |> validate_required([:action, :params, :channels])
    |> validate_inclusion(:action, @supported_actions)
    |> validate_inclusion(:step, @supported_steps)
    |> validate_channels()
  end

  def by_id(id), do: Repo.get(__MODULE__, id)
  def create(attrs), do: %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  def update(notification, attrs), do: notification |> changeset(attrs) |> Repo.update()

  defp validate_channels(changeset) do
    validate_change(changeset, :channels, fn :channels, channels ->
      if Enum.all?(channels, &(&1 in @supported_channels)) do
        []
      else
        [channels: "contains unsupported channels"]
      end
    end)
  end

  def mark_channel_processed(notification, channel) do
    attrs = %{
      String.to_existing_atom("processed_for_#{channel}") => true,
      String.to_existing_atom("processed_for_#{channel}_at") =>
        DateTime.utc_now() |> DateTime.truncate(:second)
    }

    change(notification, attrs)
  end

  def processed_for_channel?(notification, channel) do
    Map.get(notification, :"processed_for_#{channel}")
  end
end
