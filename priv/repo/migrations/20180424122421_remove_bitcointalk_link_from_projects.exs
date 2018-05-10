defmodule Sanbase.Repo.Migrations.RemoveBitcointalkLinkFromProjects do
  use Ecto.Migration

  def change do
    execute("ALTER TABLE project DROP COLUMN IF EXISTS bitcointalk_link;")
  end
end
