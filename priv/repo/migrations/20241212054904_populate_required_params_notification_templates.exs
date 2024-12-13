defmodule Sanbase.Repo.Migrations.PopulateRequiredParamsNotificationTemplates do
  use Ecto.Migration
  alias Sanbase.Notifications.NotificationTemplate
  alias Sanbase.Repo

  import Ecto.Query

  def up do
    setup()

    updates = [
      # Create action
      {["metric_created", "all", "all"], ["metrics_list"]},

      # Update action
      {["metric_updated", "before", "all"], ["metrics_list", "scheduled_at", "duration"]},
      {["metric_updated", "after", "all"], ["metrics_list"]},

      # Delete action
      {["metric_deleted", "before", "all"], ["metrics_list", "scheduled_at"]},
      {["metric_deleted", "reminder", "all"], ["metrics_list", "scheduled_at"]},
      {["metric_deleted", "after", "all"], ["metrics_list"]},

      # Alert action
      {["alert", "detected", "all"], ["metric_name", "asset_categories"]},
      {["alert", "resolved", "all"], ["metric_name"]}
    ]

    Enum.each(updates, fn {[action, step, channel], required_params} ->
      from(t in NotificationTemplate,
        where:
          t.action == ^action and
            t.step == ^step and
            t.channel == ^channel
      )
      |> Repo.update_all(set: [required_params: required_params])
    end)
  end

  def down do
    setup()

    from(t in NotificationTemplate,
      where:
        t.channel == "all" and
          t.action in ["create", "update", "delete", "alert"]
    )
    |> Repo.update_all(set: [required_params: nil])
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
