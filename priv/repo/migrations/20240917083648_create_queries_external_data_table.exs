defmodule Sanbase.Repo.Migrations.CreateQueriesExternalDataTable do
  use Ecto.Migration

  def change do
    create table(:queries_external_data) do
      add(:uuid, :string, null: false)
      add(:user_id, references(:users, on_delete: :delete_all), null: false)

      add(:name, :string, null: false)
      add(:description, :string)

      add(:storage, :string, null: false)
      add(:location, :string, null: false)

      timestamps()
    end

    create(unique_index(:queries_external_data, [:uuid]))
    create(unique_index(:queries_external_data, [:user_id, :name]))
  end
end
