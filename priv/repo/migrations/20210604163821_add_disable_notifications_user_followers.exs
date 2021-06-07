defmodule Sanbase.Repo.Migrations.AddDisableNotificationsUserFollowers do
  use Ecto.Migration

  def change do
    alter table(:user_followers) do
      add(:disable_notifications, :boolean, default: false)
    end
  end
end
