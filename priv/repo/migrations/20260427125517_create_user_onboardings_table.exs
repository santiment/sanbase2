defmodule Sanbase.Repo.Migrations.CreateUserOnboardingsTable do
  use Ecto.Migration

  def change do
    create table(:user_onboardings) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:title, :string)
      add(:goal, :string)
      add(:used_tools, {:array, :string}, default: [])
      add(:uses_behaviour_analysis, :string)

      timestamps()
    end

    create(unique_index(:user_onboardings, [:user_id]))
  end
end
