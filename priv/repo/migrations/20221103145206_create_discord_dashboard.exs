defmodule Sanbase.Repo.Migrations.CreateDiscordDashboard do
  use Ecto.Migration

  def change do
    create table(:discord_dashboard) do
      add(:panel_id, :string)
      add(:name, :string)
      add(:discord_user, :string)
      add(:channel, :string)
      add(:guild, :string)
      add(:user_id, references(:users, on_delete: :nothing))
      add(:dashboard_id, references(:dashboards, on_delete: :nothing))
      add(:pinned, :boolean, default: false)

      timestamps()
    end

    create(index(:discord_dashboard, [:user_id]))
    create(index(:discord_dashboard, [:dashboard_id]))
  end
end
