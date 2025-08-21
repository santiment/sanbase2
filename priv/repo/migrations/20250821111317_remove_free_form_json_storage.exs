defmodule Sanbase.Repo.Migrations.RemoveFreeFormJsonStorage do
  use Ecto.Migration

  def up do
    drop(table(:free_form_json_storage))
  end

  def down do
    create table(:free_form_json_storage) do
      add(:key, :string, null: false)
      add(:value, :jsonb, default: "{}", null: false)

      timestamps()
    end

    create(unique_index(:free_form_json_storage, [:key]))
  end
end
