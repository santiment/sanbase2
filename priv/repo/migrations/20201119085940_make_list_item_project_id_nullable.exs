defmodule Sanbase.Repo.Migrations.MakeListItemProjectIdNullable do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("ALTER TABLE list_items ALTER COLUMN project_id DROP NOT NULL;")
  end

  def down do
    :ok
  end
end
