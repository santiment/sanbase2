defmodule Sanbase.Repo.Migrations.CreateReports do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:reports) do
      add(:name, :string, null: false)
      add(:description, :text)
      add(:url, :string, null: false)
      add(:is_published, :boolean, default: false, null: false)
      add(:is_pro, :boolean, default: false, null: false)

      timestamps()
    end
  end
end
