defmodule Sanbase.Repo.Migrations.AddUserEntityInteractionUniqueIndex do
  use Ecto.Migration

  # Do not store the same interaction again multiple times. The code that stores
  # the interaction also rounds the
  def change do
    create(
      unique_index(:user_entity_interactions, [
        :user_id,
        :entity_type,
        :entity_id,
        :interaction_type,
        :inserted_at
      ])
    )
  end
end
