defmodule Sanbase.Repo.Migrations.AddPppPlans do
  use Ecto.Migration

  def up do
    setup()

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_ppp, is_private) VALUES
    (206,'PRO',2,1500,'USD','month',0, 't', 't'),
    (207,'PRO',2,15900,'USD','year',0, 't', 't'),
    (208,'PRO_PLUS',2,7500,'USD','month',0, 't', 't'),
    (209,'PRO_PLUS',2,81000,'USD','year',0, 't', 't')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (206,207,208,209)")
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
