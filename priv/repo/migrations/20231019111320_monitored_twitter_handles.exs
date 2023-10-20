defmodule Sanbase.Repo.Migrations.MonitoredTwitterHandles do
  use Ecto.Migration

  def change do
    create table(:monitored_twitter_handles) do
      add(:handle, :string, null: false)
      add(:origin, :string, null: false)
      add(:notes, :text)

      add(:user_id, references(:users), on_delete: :nilify_all)

      timestamps()
    end

    create(unique_index(:monitored_twitter_handles, [:handle]))
  end
end
