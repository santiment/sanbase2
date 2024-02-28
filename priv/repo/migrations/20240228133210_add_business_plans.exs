defmodule Sanbase.Repo.Migrations.AddBusinessPlans do
  use Ecto.Migration

  def up do
    setup()

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private) VALUES
    (105,'BUSINESS_PRO',1,42000,'USD','month',20,'t'),
    (106,'BUSINESS_PRO',1,478800,'USD','year',21,'t'),
    (107,'BUSINESS_MAX',1,99900,'USD','month',22,'t'),
    (108,'BUSINESS_MAX',1,1138800,'USD','year',23,'t')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (206,207,208,209)")
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
