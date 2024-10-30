defmodule Sanbase.Repo.Migrations.AddManualNotificationActionType do
  use Ecto.Migration

  def up do
    execute("ALTER TYPE notification_action_type ADD VALUE IF NOT EXISTS 'manual'")
  end

  def down do
    :ok
  end
end
