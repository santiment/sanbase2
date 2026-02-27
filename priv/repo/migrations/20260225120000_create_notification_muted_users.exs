defmodule Sanbase.Repo.Migrations.CreateNotificationMutedUsers do
  use Ecto.Migration

  @table :notification_muted_users

  def change do
    create table(@table, primary_key: false) do
      add(:user_id, references(:users, on_delete: :delete_all), primary_key: true)
      add(:muted_user_id, references(:users, on_delete: :delete_all), primary_key: true)

      timestamps(updated_at: false)
    end

    create(constraint(@table, :cannot_mute_self, check: "user_id != muted_user_id"))

    create(index(@table, [:muted_user_id]))
  end
end
