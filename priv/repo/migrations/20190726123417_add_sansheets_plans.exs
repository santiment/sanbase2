defmodule Sanbase.Repo.Migrations.AddSansheetsPlans do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
      (21, 'FREE', 3, 0, 'USD', 'month'),
      (22, 'BASIC', 3, 8900, 'USD', 'month'),
      (23, 'PRO', 3, 18900, 'USD', 'month'),
      (24, 'ENTERPRISE', 3, 0, 'USD', 'month'),
      (25, 'BASIC', 3, 96120, 'USD', 'year'),
      (26, 'PRO', 3, 204120, 'USD', 'year'),
      (27, 'ENTERPRISE', 3, 0, 'USD', 'year')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (21, 22, 23, 24, 25, 26, 27)")
  end
end
