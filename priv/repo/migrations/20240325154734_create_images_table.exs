defmodule Sanbase.Repo.Migrations.CreateImagesTable do
  use Ecto.Migration

  def change do
    create table(:images) do
      add(:url, :text, null: false)
      add(:name, :string, null: false)

      add(:notes, :text)

      timestamps()
    end
  end
end
