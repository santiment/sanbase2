defmodule Sanbase.Repo.Migrations.UpdateNotificationTemplatesIndex do
  use Ecto.Migration

  def up do
    execute("DROP INDEX IF EXISTS notification_templates_action_type_step_channel_index")
    execute("DROP INDEX IF EXISTS notification_templates_action_type_step_index")

    create(unique_index(:notification_templates, [:action, :step, :channel, :mime_type]))
  end

  def down do
    :ok
  end
end
