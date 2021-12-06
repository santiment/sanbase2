defmodule Sanbase.Repo.Migrations.AddSharedSubscriptionMapping do
  use Ecto.Migration

  def change do
    create table(:linked_users) do
      add(:user_id, references(:users))
      add(:primary_user_id, references(:users))
    end
  end
end
