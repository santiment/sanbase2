defmodule Sanbase.Repo.Migrations.AddManualNotificationActionType do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("ALTER TYPE public.notification_action_type ADD VALUE IF NOT EXISTS 'manual'")
  end

  def down do
    :ok
  end
end
