defmodule Sanbase.Repo.Migrations.AddUrlToSanbaseNotifications do
  use Ecto.Migration

  def change do
    alter table(:sanbase_notifications) do
      add(:url, :text)
    end
  end
end
