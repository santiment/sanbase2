defmodule Sanbase.Repo.Migrations.AddUserEntityInteractionUniqueIndex do
  use Ecto.Migration

  # Do not store the same interaction again multiple times. The code that stores
  # the interaction also rounds the
  @unique_index_fields [
    :user_id,
    :entity_type,
    :entity_id,
    :interaction_type,
    :inserted_at
  ]
  def up do
    # Drop all interactions that have the same value in all of the fields
    # defined in the unique index, leaving only one of them.
    execute("""
    DELETE FROM user_entity_interactions a
    USING user_entity_interactions b
    WHERE
        a.id < b.id
        AND a.user_id = b.user_id
        AND a.entity_type = b.entity_type
        AND a.entity_id = b.entity_id
        AND a.interaction_type = b.interaction_type
        AND a.inserted_at = b.inserted_at
    ;
    """)

    create(unique_index(:user_entity_interactions, @unique_index_fields))
  end

  def down do
    drop(unique_index(:user_entity_interactions, @unique_index_fields))
  end
end
