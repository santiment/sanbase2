defmodule Sanbase.Repo.Migrations.AddIsDeletedColumnToTables do
  @moduledoc false
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end

    alter table(:user_triggers) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end

    alter table(:chart_configurations) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end

    alter table(:user_lists) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end

    alter table(:comments) do
      add(:is_deleted, :boolean, default: false)
      add(:is_hidden, :boolean, default: false)
    end
  end
end
