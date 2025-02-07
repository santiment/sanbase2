defmodule Sanbase.Repo.Migrations.UpdateNotificationTemplatesIndex do
  use Ecto.Migration

  def change do
    drop(unique_index(:notification_templates, [:action, :step, :channel]))

    create(unique_index(:notification_templates, [:action, :step, :channel, :mime_type]))
  end
end
