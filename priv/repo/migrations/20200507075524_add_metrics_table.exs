defmodule Sanbase.Repo.Migrations.AddMetricsTable do
  use Ecto.Migration

  def change do
    create table("metrics") do
      add(:name, :string, null: false)
      timestamps()
    end
  end
end
