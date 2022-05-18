defmodule Sanbase.Repo.Migrations.CreateUserEntityInteractionsTable do
  use Ecto.Migration

  def change do
    create table(:user_entity_interactions) do
      add(:user_id, references(:users))
      add(:entity_type, :string)
      add(:entity_id, :integer)
      add(:entity_details, :jsonb)
      add(:interaction_type, :string)

      timestamps()
    end

    create(index(:user_entity_interactions, [:user_id]))
    create(index(:user_entity_interactions, [:entity_type]))
    create(index(:user_entity_interactions, [:entity_type, :entity_id]))
    create(index(:user_entity_interactions, [:interaction_type]))
  end
end
