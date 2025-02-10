defmodule Sanbase.Repo.Migrations.AddSubscriptionStatus do
  @moduledoc false
  use Ecto.Migration

  def up do
    SubscriptionStatusEnum.create_type()

    alter table(:subscriptions) do
      add(:status, SubscriptionStatusEnum.type(), null: false, default: "active")
    end
  end

  def down do
    alter table(:subscriptions) do
      remove(:status)
    end

    SubscriptionStatusEnum.drop_type()
  end
end
