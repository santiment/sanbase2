defmodule Sanbase.Repo.Migrations.UpdateNotificationTemplates do
  use Ecto.Migration

  def up do
    # Update action_type values
    execute("""
    UPDATE notification_templates
    SET action_type = CASE action_type
      WHEN 'create' THEN 'metric_created'
      WHEN 'update' THEN 'metric_updated'
      WHEN 'delete' THEN 'metric_deleted'
    END
    WHERE action_type IN ('create', 'update', 'delete')
    """)

    # Set NULL steps to 'all'
    execute("""
    UPDATE notification_templates
    SET step = 'all'
    WHERE step IS NULL
    """)
  end

  def down do
    # Revert action_type values
    execute("""
    UPDATE notification_templates
    SET action_type = CASE action_type
      WHEN 'metric_created' THEN 'create'
      WHEN 'metric_updated' THEN 'update'
      WHEN 'metric_deleted' THEN 'delete'
    END
    WHERE action_type IN ('metric_created', 'metric_updated', 'metric_deleted')
    """)

    # Revert 'all' steps back to NULL where appropriate
    execute("""
    UPDATE notification_templates
    SET step = NULL
    WHERE step = 'all'
    """)
  end
end
