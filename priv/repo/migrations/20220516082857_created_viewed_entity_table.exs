defmodule Sanbase.Repo.Migrations.CreatedViewedEntityTable do
  use Ecto.Migration

  def change do
    create table(:user_usage_activities) do
      add(:user_id, references(:users))
      add(:entity_type, :string)
      add(:entity_id, :integer)
      add(:entity_details, :jsonb)
      add(:activity_type, :string)

      timestamps()
    end

    create(index(:user_usage_activities, [:user_id]))
    create(index(:user_usage_activities, [:entity_type]))
    create(index(:user_usage_activities, [:entity_type, :entity_id]))
    create(index(:user_usage_activities, [:activity_type]))
  end
end
