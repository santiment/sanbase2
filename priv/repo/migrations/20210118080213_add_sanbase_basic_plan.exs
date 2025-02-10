defmodule Sanbase.Repo.Migrations.AddSanbaseBasicPlan do
  @moduledoc false
  use Ecto.Migration

  def up do
    # already deprecated plans, now deleted
    execute("DELETE FROM plans WHERE id IN (12, 14, 15, 17)")

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, "order") VALUES
      (205,'BASIC',2,900,'USD','month',9)
      ON CONFLICT DO NOTHING
    """)
  end

  def down do
    :ok
  end
end
