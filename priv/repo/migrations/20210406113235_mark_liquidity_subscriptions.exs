defmodule Sanbase.Repo.Migrations.MarkLiquiditySubscriptions do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    UPDATE subscriptions
    SET type = 'liquidity'
    WHERE id IN (
      SELECT id FROM subscriptions WHERE stripe_id is NULL
    );
    """)
  end

  def down do
    execute("""
    UPDATE subscriptions
    SET type = 'fiat'
    WHERE id IN (
      SELECT id FROM subscriptions WHERE stripe_id is NULL
    );
    """)
  end
end
