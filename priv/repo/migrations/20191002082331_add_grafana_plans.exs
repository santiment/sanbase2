defmodule Sanbase.Repo.Migrations.AddGrafanaPlans do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
      (41, 'BASIC', 4, 5000, 'USD', 'month'),
      (42, 'PRO', 4, 14000, 'USD', 'month'),
      (43, 'PREMIUM', 4, 29000, 'USD', 'month'),
      (44, 'BASIC', 4, 54000, 'USD', 'year'),
      (45, 'PRO', 4, 151200, 'USD', 'year'),
      (46, 'PREMIUM', 4, 313200, 'USD', 'year')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (41, 42, 43, 44, 45, 46)")
  end
end
