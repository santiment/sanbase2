defmodule Sanbase.Repo.Migrations.CreateReports do
  use Ecto.Migration

  def change do
    create table(:reports) do
      add(:name, :string)
      add(:description, :text)
      add(:url, :string)
      add(:is_published, :boolean, default: false, null: false)
      add(:is_pro, :boolean, default: false, null: false)

      timestamps()
    end
  end
end
