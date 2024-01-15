defmodule Sanbase.Repo.Migrations.AddFreeFormJsonStorage do
  use Ecto.Migration

  def change do
    create table(:free_form_json_storage) do
      add(:key, :string, nil: false)
      add(:value, :jsonb, default: "{}", nil: false)

      timestamps()
    end

    create(unique_index(:free_form_json_storage, [:key]))
  end
end
