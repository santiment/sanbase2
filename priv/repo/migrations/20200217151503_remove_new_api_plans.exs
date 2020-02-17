defmodule Sanbase.Repo.Migrations.RemoveNewApiPlans do
  use Ecto.Migration

  def up do
    execute("DELETE FROM plans where id IN (101, 102, 103, 104)")
  end

  def down do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
      (101, 'ESSENTIAL', 1, 16000, 'USD', 'month'),
      (102, 'PRO', 1, 42000, 'USD', 'month'),
      (103, 'ESSENTIAL', 1, 178800, 'USD', 'year'),
      (104, 'PRO', 1, 478800, 'USD', 'year')
    """)
  end
end
