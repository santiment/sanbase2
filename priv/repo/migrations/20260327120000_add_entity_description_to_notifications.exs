defmodule Sanbase.Repo.Migrations.AddEntityDescriptionToNotifications do
  use Ecto.Migration

  def change do
    alter table(:sanbase_notifications) do
      add(:entity_description, :text)
    end
  end
end
