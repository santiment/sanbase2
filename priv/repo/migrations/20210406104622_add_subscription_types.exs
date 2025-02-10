defmodule Sanbase.Repo.Migrations.AddSubscriptionTypes do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      CREATE TYPE public.subscription_type AS ENUM ('fiat', 'liquidity', 'burning_regular', 'burning_nft');
    EXCEPTION
      WHEN duplicate_object THEN null;
    END $$;
    """)

    alter table(:subscriptions) do
      add(:type, :subscription_type, null: false, default: "fiat")
    end
  end

  def down do
    alter table(:subscriptions) do
      remove(:type)
    end

    SubscriptionType.drop_type()
  end
end
