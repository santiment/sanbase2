defmodule Sanbase.Repo.Migrations.AddUserFollowersTable do
  use Ecto.Migration

  @table :user_followers

  def change do
    create table(@table, primary_key: false) do
      add(:user_id, references(:users), primary_key: true)
      add(:follower_id, references(:users), primary_key: true)
      timestamps(updated_at: false)
    end

    create(unique_index(@table, [:user_id, :follower_id]))
    create(constraint(@table, :user_cannot_follow_self, check: "user_id != follower_id"))
  end
end
