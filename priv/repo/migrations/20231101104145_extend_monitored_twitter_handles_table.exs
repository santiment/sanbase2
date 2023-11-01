defmodule Sanbase.Repo.Migrations.ExtendMonitoredTwitterHandlesTable do
  use Ecto.Migration

  def change do
    alter table(:monitored_twitter_handles) do
      add(:comment, :text)
    end
  end
end
