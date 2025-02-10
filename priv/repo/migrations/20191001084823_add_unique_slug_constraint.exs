defmodule Sanbase.Repo.Migrations.AddUniqueSlugConstraint do
  @moduledoc false
  use Ecto.Migration

  def change do
    create(unique_index(:project, [:slug]))
  end
end
