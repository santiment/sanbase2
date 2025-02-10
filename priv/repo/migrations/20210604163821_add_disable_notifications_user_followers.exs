defmodule Sanbase.Repo.Migrations.AddisNotificationDisabledUserFollowers do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:user_followers) do
      add(:is_notification_disabled, :boolean, default: false)
    end
  end
end
