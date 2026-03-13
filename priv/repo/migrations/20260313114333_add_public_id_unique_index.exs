defmodule Sanbase.Repo.Migrations.AddPublicIdUniqueIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  def change do
    create(unique_index(:users, [:public_id], concurrently: true))
  end
end
