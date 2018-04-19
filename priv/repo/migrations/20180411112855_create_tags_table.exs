defmodule Sanbase.Repo.Migrations.CreateTagsTable do
  use Ecto.Migration

  def change do
    create table(:tags) do
      add(:name, :string)
    end

    create(unique_index(:tags, :name))
  end
end
