defmodule Sanbase.Repo.Migrations.AddNotificationsIndexes do
  use Ecto.Migration

  def change do
    create(index(:sanbase_notifications, [:inserted_at]))
    create(index(:sanbase_notifications_read_status, [:user_id]))
  end
end
