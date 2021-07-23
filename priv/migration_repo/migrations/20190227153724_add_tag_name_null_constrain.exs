defmodule Sanbase.Repo.Migrations.AddTagNameNullConstrain do
  use Ecto.Migration

  def up do
    alter table(:tags) do
      modify(:name, :string, null: false)
    end
  end

  def down do
    alter table(:tags) do
      modify(:name, :string, null: true)
    end
  end
end
