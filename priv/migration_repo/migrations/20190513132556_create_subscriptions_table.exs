defmodule Sanbase.Repo.Migrations.CreateSubscriptionsTable do
  use Ecto.Migration

  def change do
    create table(:subscriptions) do
      add(:user_id, references(:users, on_delete: :delete_all), null: false)
      add(:plan_id, references(:plans, on_delete: :delete_all), null: false)
      add(:stripe_id, :string)
    end
  end
end
