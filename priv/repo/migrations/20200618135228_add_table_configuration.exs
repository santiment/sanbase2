defmodule Sanbase.Repo.Migrations.AddTableConfiguration do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:table_configurations) do
      add(:user_id, references(:users))
      add(:title, :string, null: false)
      add(:description, :text)
      add(:is_public, :boolean, default: false, null: false)
      add(:page_size, :integer, default: 50)
      add(:columns, :jsonb)

      timestamps()
    end
  end
end
