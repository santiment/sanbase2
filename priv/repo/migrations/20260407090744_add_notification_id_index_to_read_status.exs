defmodule Sanbase.Repo.Migrations.AddNotificationIdIndexToReadStatus do
  use Ecto.Migration

  def change do
    create(index(:sanbase_notifications_read_status, [:notification_id]))
  end
end
