defmodule Sanbase.Repo.Migrations.CreatePlansTable do
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
      (1, 'FREE', 1, 0, 'USD', 'month', '#{ApiAccessChecker.free() |> Jason.encode!()}'),
      (2, 'ESSENTIAL', 1, 11900, 'USD', 'month', '#{
      ApiAccessChecker.essential() |> Jason.encode!()
    }'),
      (3, 'PRO', 1, 35900, 'USD', 'month', '#{ApiAccessChecker.pro() |> Jason.encode!()}'),
      (4, 'PREMIUM', 1, 71900, 'USD', 'month', '#{ApiAccessChecker.premium() |> Jason.encode!()}'),
      (5, 'CUSTOM', 1, 0, 'USD', 'month', '#{ApiAccessChecker.premium() |> Jason.encode!()}')
    """)
  end

  def down do
    drop(table(:plans))
  end
end
