defmodule Sanbase.Repo.Migrations.AddSanbasePlans do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval) VALUES
      (11, 'FREE', 2, 0, 'USD', 'month'),
      (12, 'BASIC', 2, 1100, 'USD', 'month'),
      (13, 'PRO', 2, 5100, 'USD', 'month'),
      (14, 'ENTERPRISE', 2, 0, 'USD', 'month'),
      (15, 'BASIC', 2, 10800, 'USD', 'year'),
      (16, 'PRO', 2, 54000, 'USD', 'year'),
      (17, 'ENTERPRISE', 2, 0, 'USD', 'year')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (11, 12, 13, 14, 15, 16, 17)")
  end
end
