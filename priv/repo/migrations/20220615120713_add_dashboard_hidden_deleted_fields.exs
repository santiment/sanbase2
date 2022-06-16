defmodule Sanbase.Repo.Migrations.AddDashboardHiddenDeletedFields do
  use Ecto.Migration

  def change do
    alter table(:dashboards) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end
  end
end
