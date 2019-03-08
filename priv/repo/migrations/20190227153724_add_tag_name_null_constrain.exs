defmodule Sanbase.Repo.Migrations.AddTagNameNullConstrain do
  use Ecto.Migration

  def change do
    alter table(:tags) do
      modify(:name, :string, null: false)
    end
  end
end
