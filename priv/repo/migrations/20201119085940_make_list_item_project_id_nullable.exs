defmodule Sanbase.Repo.Migrations.MakeListItemProjectIdNullable do
  use Ecto.Migration

  def change do
    execute("ALTER TABLE list_items ALTER COLUMN project_id DROP NOT NULL;")
  end
end
