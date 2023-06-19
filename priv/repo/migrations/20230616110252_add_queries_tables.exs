defmodule Sanbase.Repo.Migrations.AddQueriesTables do
  use Ecto.Migration

  def change do
    create table(:queries) do
      # Identifiers
      # add(:id, :integer, ...)
      add(:uuid, :string, null: false, unique: true)

      # Reference to the original query
      add(:origin_id, :integer, null: true, unique: false)
      add(:origin_uuid, :string, null: true, unique: false)

      # Basic fields
      add(:name, :text)
      add(:description, :text)
      add(:is_public, :boolean, default: true)

      # Settings
      add(:settings, :jsonb)

      # SQL Query
      add(:sql_query, :text, default: "")
      add(:sql_parameters, :map, default: %{})

      # Ownership
      add(:user_id, references(:users), null: false)

      # Fields related to timeline hiding and reversible-deletion
      add(:is_hidden, :boolean, default: false)
      add(:is_deleted, :boolean, default: false)

      timestamps()
    end

    # Index used to fetch all queries for a user
    create(index(:queries, [:user_id]))
  end
end
