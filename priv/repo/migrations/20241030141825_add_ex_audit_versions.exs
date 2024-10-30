defmodule Sanbase.Repo.Migrations.AddExAuditVersions do
  use Ecto.Migration

  def change do
    create table(:versions) do
      # The patch in Erlang External Term Format
      add(:patch, :binary)

      # supports UUID and other types as well
      add(:entity_id, :integer)

      # name of the table the entity is in
      add(:entity_schema, :string)

      # type of the action that has happened to the entity (created, updated, deleted)
      add(:action, :string)

      # when has this happened
      add(:recorded_at, :utc_datetime)

      # was this change part of a rollback?
      add(:rollback, :boolean, default: false)

      # optional fields that you can define yourself
      # for example, it's a good idea to track who did the change
      add(:user_id, references(:users, on_update: :update_all, on_delete: :nilify_all))
    end

    # create this if you are going to have more than a hundred of thousands of versions
    create(index(:versions, [:entity_schema, :entity_id]))
  end
end
