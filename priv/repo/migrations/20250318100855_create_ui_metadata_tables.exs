defmodule Sanbase.Repo.Migrations.CreateUiMetadataTables do
  use Ecto.Migration

  def change do
    create table(:ui_metadata_categories) do
      add(:name, :string, null: false)
      add(:display_order, :integer, null: false)

      timestamps()
    end

    create(unique_index(:ui_metadata_categories, [:name]))

    create table(:ui_metadata_groups) do
      add(:name, :string, null: false)
      add(:category_id, references(:ui_metadata_categories, on_delete: :delete_all), null: false)

      timestamps()
    end

    create(unique_index(:ui_metadata_groups, [:name, :category_id]))
  end
end
