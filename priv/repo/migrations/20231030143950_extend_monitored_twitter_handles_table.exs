defmodule Sanbase.Repo.Migrations.ExtendMonitoredTwitterHandlesTable do
  use Ecto.Migration

  def change do
    alter table(:monitored_twitter_handles) do
      add(:approved_by, :text)
      add(:declined_by, :text)
    end
  end
end
