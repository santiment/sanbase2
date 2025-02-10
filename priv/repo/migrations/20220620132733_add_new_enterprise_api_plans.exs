defmodule Sanbase.Repo.Migrations.AddNewEnterpriseApiPlans do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order") VALUES
      (105,'ENTERPRISE_BASIC',1, 150000,'USD','month', 14),
      (106,'ENTERPRISE_PLUS',1, 250000,'USD','month', 15)
      ON CONFLICT DO NOTHING
    """)
  end

  def down do
    execute("DELETE FROM plans WHERE id IN (105, 106)")
  end
end
