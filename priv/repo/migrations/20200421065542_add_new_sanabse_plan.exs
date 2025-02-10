defmodule Sanbase.Repo.Migrations.AddNewSanabsePlan do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order") VALUES
      (201,'PRO',2,4900,'USD','month',0),
      (202,'PRO',2,52900,'USD','year',0)
      ON CONFLICT DO NOTHING
    """)

    execute("UPDATE plans SET is_deprecated='t' where id IN (12, 13, 15, 16)")
  end

  def down do
    execute("DELETE FROM plans WHERE id IN (201, 202)")
    execute("UPDATE plans SET is_deprecated='f' where id IN (12, 13, 15, 16)")
  end
end
