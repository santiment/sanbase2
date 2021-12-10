defmodule Sanbase.Repo.Migrations.AddLinkedUsersTable do
  use Ecto.Migration

  def change do
    create table(:linked_users) do
      add(:primary_user_id, references(:users), null: false)
      add(:secondary_user_id, references(:users), null: false)

      timestamps()
    end

    # One user can be added only once as a secondary user. This is enforced
    # at a database level.
    # One primary user can have only a limited number of secondary users.
    # This second limit is applied at application level.
    create(unique_index(:linked_users, [:secondary_user_id]))

    create table(:linked_users_candidates) do
      add(:primary_user_id, references(:users), null: false)
      add(:secondary_user_id, references(:users), null: false)
      add(:token, :string, null: false)
      add(:is_confirmed, :boolean, default: false, null: false)

      timestamps()
    end

    # One primary-secondary user pair could have more than one
    # candidate at the same time. This is to avoid confusion with
    # lost links, forgotten unopened links, etc.
    create(unique_index(:linked_users_candidates, [:token]))
  end
end
