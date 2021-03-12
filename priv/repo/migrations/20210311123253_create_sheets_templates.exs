defmodule Sanbase.Repo.Migrations.CreateSheetsTemplates do
  use Ecto.Migration

  def change do
    create table(:sheets_templates) do
      add(:name, :string, null: false)
      add(:description, :text)
      add(:url, :string, null: false)
      add(:is_pro, :boolean, default: false, null: false)

      timestamps()
    end
  end
end
