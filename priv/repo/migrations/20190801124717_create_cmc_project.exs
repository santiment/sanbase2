defmodule Sanbase.Repo.Migrations.CreateCmcProject do
  use Ecto.Migration

  @table :cmc_project
  def change do
    create table(@table) do
      add(:project_id, references(:project, on_delete: :delete_all), null: false)
      add(:logos_uploaded_at, :naive_datetime)
      add(:logo_hash, :string)
      timestamps()
    end

    create(unique_index(@table, [:project_id]))
  end
end
