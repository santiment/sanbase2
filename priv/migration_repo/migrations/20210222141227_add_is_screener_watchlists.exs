defmodule Sanbase.Repo.Migrations.AddIsScreenerWatchlists do
  use Ecto.Migration

  def change do
    alter table(:user_lists) do
      add(:is_screener, :boolean, default: false)
    end
  end
end
