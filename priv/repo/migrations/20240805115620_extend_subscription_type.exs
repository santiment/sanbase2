defmodule Sanbase.Repo.Migrations.ExtendSubscriptionType do
  use Ecto.Migration

  def up do
    execute("""
    DO $$ BEGIN
      ALTER TYPE public.subscription_type ADD VALUE IF NOT EXISTS 'sanr_points_nft';
    END $$;
    """)
  end

  def down do
    # Dropping values from an enum is not supported
    :ok
  end
end
