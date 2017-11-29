defmodule Sanbase.Repo.Migrations.IcosDropPrprojectUk do
  use Ecto.Migration

  def up do
    drop unique_index(:icos, [:project_id])
  end

  def down do
    create unique_index(:icos, [:project_id])
  end
end
