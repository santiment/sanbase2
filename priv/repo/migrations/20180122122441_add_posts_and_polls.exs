defmodule Sanbase.Repo.Migrations.AddPostsAndPolls do
  use Ecto.Migration

  def change do
    create table(:polls) do
      add :start_at, :naive_datetime, null: false
      add :end_at, :naive_datetime, null: false
      timestamps()
    end

    create unique_index(:polls, [:start_at])

    create table(:posts) do
      add :poll_id, references(:polls), null: false
      add :user_id, references(:users), null: false
      add :title, :string, null: false
      add :link, :string, null: false
      add :approved_at, :naive_datetime

      timestamps()
    end

    create table(:votes) do
      add :post_id, references(:posts)
      add :user_id, references(:users)

      timestamps()
    end

    create unique_index(:votes, [:post_id, :user_id])

    alter table(:users) do
      add :san_balance, :integer
      add :san_balance_updated_at, :naive_datetime
    end
  end
end
