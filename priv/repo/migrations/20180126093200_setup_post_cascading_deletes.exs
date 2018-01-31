defmodule Sanbase.Repo.Migrations.SetupPostCascadingDeletes do
  use Ecto.Migration

  def change do
    drop(table(:votes))
    drop(table(:posts))
    drop(table(:polls))

    create table(:polls) do
      add(:start_at, :naive_datetime, null: false)
      add(:end_at, :naive_datetime, null: false)
      timestamps()
    end

    create(unique_index(:polls, [:start_at]))

    create table(:posts) do
      add(:poll_id, references(:polls, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:title, :string, null: false)
      add(:link, :string, null: false)
      add(:approved_at, :naive_datetime)

      timestamps()
    end

    create table(:votes) do
      add(:post_id, references(:posts, on_delete: :delete_all), null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:votes, [:post_id, :user_id]))
  end
end
