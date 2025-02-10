defmodule Sanbase.Repo.Migrations.AddDashboardHistoryTable do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:dashboards_history) do
      add(:dashboard_id, references(:dashboards), on_delete: :delete_all)
      add(:user_id, references(:users), on_delete: :delete_all)
      add(:panels, :jsonb)
      add(:name, :string)
      add(:description, :text)
      add(:is_public, :boolean)

      add(:message, :text)
      add(:hash, :text)

      timestamps()
    end

    create(index(:dashboards_history, :dashboard_id))
    create(index(:dashboards_history, :hash))
  end
end
