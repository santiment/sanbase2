defmodule Sanbase.Repo.Migrations.AddPlansRestrictionField do
  use Ecto.Migration

  def change do
    alter table(:plans) do
      add(:has_custom_restrictions, :boolean, null: false, default: false)
      add(:restrictions, :jsonb, null: true, default: nil)
    end
  end
end
