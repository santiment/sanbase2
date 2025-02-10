defmodule Sanbase.Repo.Migrations.AddV2Plans do
  @moduledoc false
  use Ecto.Migration

  def up do
    setup()

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order", is_private) VALUES
    (210,'MAX',2,24900,'USD','month',0, 't'),
    (211,'MAX',2,270000,'USD','year',0, 't'),
    (107,'BUSINESS_PRO',1,42000,'USD','month',20,'t'),
    (108,'BUSINESS_PRO',1,478800,'USD','year',21,'t'),
    (109,'BUSINESS_MAX',1,99900,'USD','month',22,'t'),
    (110,'BUSINESS_MAX',1,1138800,'USD','year',23,'t')
    """)
  end

  def down do
    execute("DELETE FROM plans where id IN (105, 106, 107, 108, 210, 211)")
  end

  defp setup do
    Application.ensure_all_started(:tzdata)
  end
end
