defmodule Sanbase.Notifications.Notification do
  use Ecto.Schema
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Notifications.NotificationTemplate

  @supported_actions ["metric_created", "metric_updated", "metric_deleted", "message", "alert"]
  @supported_channels ["discord", "email"]
  @supported_steps ["all", "before", "reminder", "after", "detected", "resolved"]
  @supported_statuses ["available", "completed", "failed", "discarded", "cancelled"]

  def supported_channels, do: @supported_channels
  def supported_actions, do: @supported_actions
  def supported_steps, do: @supported_steps
  def supported_statuses, do: @supported_statuses

  schema "notifications" do
    field(:action, :string)
    field(:params, :map)
    field(:channel, :string)
    field(:step, :string, default: "all")
    field(:status, :string, default: "available")
    field(:job_id, :integer)
    field(:is_manual, :boolean, default: false)

    belongs_to(:metric_registry, Registry)
    belongs_to(:notification_template, NotificationTemplate)

    timestamps()
  end

  def changeset(notification, attrs) do
    notification
    |> cast(attrs, [
      :action,
      :params,
      :channel,
      :step,
      :status,
      :job_id,
      :is_manual,
      :metric_registry_id,
      :notification_template_id
    ])
    |> validate_required([:action, :params, :channel])
    |> validate_inclusion(:action, @supported_actions)
    |> validate_inclusion(:step, @supported_steps)
    |> validate_inclusion(:channel, @supported_channels)
    |> validate_inclusion(:status, @supported_statuses)
    |> foreign_key_constraint(:metric_registry_id)
    |> foreign_key_constraint(:notification_template_id)
  end

  def by_id(id), do: Repo.get(__MODULE__, id)
  def create(attrs), do: %__MODULE__{} |> changeset(attrs) |> Repo.insert()
  def update(notification, attrs), do: notification |> changeset(attrs) |> Repo.update()
end
