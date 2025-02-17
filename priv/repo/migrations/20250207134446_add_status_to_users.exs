defmodule Sanbase.Repo.Migrations.AddStatusToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      add(:metric_access_level, :string, null: false, default: "released")
    end
  end
end
