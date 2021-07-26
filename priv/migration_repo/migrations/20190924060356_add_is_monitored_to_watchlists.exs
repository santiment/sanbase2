defmodule Sanbase.Repo.Migrations.AddIsMonitoredToWatchlists do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:is_monitored, :boolean, default: false)
    end
  end
end
