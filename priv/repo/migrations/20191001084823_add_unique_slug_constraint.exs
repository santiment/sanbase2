defmodule Sanbase.Repo.Migrations.AddUniqueSlugConstraint do
  use Ecto.Migration

  def change do
    create(unique_index(:project, [:slug]))
  end
end
