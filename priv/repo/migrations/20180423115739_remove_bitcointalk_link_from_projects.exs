defmodule Sanbase.Repo.Migrations.RemoveBitcointalkLinkFromProjects do
  use Ecto.Migration

  def up do
    alter table(:project) do
      remove(:bitcointalk_link)
    end
  end

  def down do
    raise Ecto.MigrationError, "Irreversible migration!"
  end
end
