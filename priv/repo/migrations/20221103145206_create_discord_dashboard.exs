defmodule Sanbase.Repo.Migrations.CreateDiscordDashboard do
  @moduledoc false
  use Ecto.Migration

  def change do
    create table(:discord_dashboards) do
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

    create(index(:discord_dashboards, [:user_id]))
    create(index(:discord_dashboards, [:dashboard_id]))
  end
end
