defmodule Sanbase.Repo.Migrations.AddMonitoredTwitterHandlesApprovalStatus do
  use Ecto.Migration

  def change do
    alter table(:monitored_twitter_handles) do
      add(:status, :string, default: "pending_approval")
    end
  end
end
