defmodule Sanbase.Repo.Migrations.DummyMigrationOnlyForStage do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:some_dummy_column, :string)
    end

    alter table(:plans) do
      remove(:some_dummy_column)
    end
  end
end
