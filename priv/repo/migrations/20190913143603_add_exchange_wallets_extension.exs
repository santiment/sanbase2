defmodule Sanbase.Repo.Migrations.AddExchangeWalletsExtension do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()

    execute("""
    INSERT INTO products (id, name) VALUES
      (5, 'Exchange Wallets by Santiment')
    """)

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
      (51, 'EXTENSION', 5, 20000, 'USD', 'month'),
      (52, 'EXTENSION', 5, 216000, 'USD', 'year')
    """)
  end

  def down do
    execute("DELETE FROM products where id IN (5)")
    execute("DELETE FROM plan where id IN (51, 52)")
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
    Application.ensure_all_started(:stripity_stripe)
  end
end
