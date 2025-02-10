defmodule Sanbase.Repo.Migrations.AddSanbaseProPlusPlan do
  @moduledoc false
  use Ecto.Migration

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order") VALUES
      (203,'PRO_PLUS',2,24900,'USD','month',7),
      (204,'PRO_PLUS',2,270000,'USD','year',5)
      ON CONFLICT DO NOTHING
    """)

    execute("UPDATE plans SET is_deprecated='t' where id IN (14, 17)")
  end

  def down do
    execute("DELETE FROM plans WHERE id IN (203, 204)")
    execute("UPDATE plans SET is_deprecated='f' where id IN (14, 17)")
  end
end
