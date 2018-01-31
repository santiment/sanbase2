defmodule Sanbase.Repo.Migrations.CreateProjectTransparencyStatuses do
  use Ecto.Migration

  def change do
    create table(:project_transparency_statuses) do
      add(:name, :string, null: false)
    end

    create(unique_index(:project_transparency_statuses, [:name]))
  end
end
