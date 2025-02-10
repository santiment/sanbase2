defmodule Sanbase.Repo.Migrations.CreatePlansTable do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Billing.Plan.AccessChecker

  @table :plans
  def up do
    create table(@table) do
      add(:name, :string, null: false)
      add(:amount, :integer, null: false)
      add(:currency, :string, null: false)
      add(:interval, :interval, null: false)
      add(:product_id, references(:products), null: false)
      add(:stripe_id, :string)
      add(:access, :jsonb)
    end

    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, access) VALUES
      (1, 'FREE', 1, 0, 'USD', 'month', '#{Jason.encode!(ApiAccessChecker.free())}'),
      (2, 'ESSENTIAL', 1, 11900, 'USD', 'month', '#{Jason.encode!(ApiAccessChecker.essential())}'),
      (3, 'PRO', 1, 35900, 'USD', 'month', '#{Jason.encode!(ApiAccessChecker.pro())}'),
      (4, 'PREMIUM', 1, 71900, 'USD', 'month', '#{Jason.encode!(ApiAccessChecker.premium())}'),
      (5, 'CUSTOM', 1, 0, 'USD', 'month', '#{Jason.encode!(ApiAccessChecker.premium())}')
    """)
  end

  def down do
    drop(table(:plans))
  end
end
