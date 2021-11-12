defmodule Sanbase.Repo.Migrations.AddSharedAccessTokensTable do
  use Ecto.Migration

  def change do
    create table(:shared_access_tokens) do
      add(:uuid, :string, null: false, unique: true)

      add(:user_id, references(:users), null: false, on_delete: :delete_all)
      add(:chart_configuration_id, references(:chart_configurations), null: false)

      timestamps()
    end

    create(unique_index(:shared_access_tokens, [:uuid]))
  end
end
