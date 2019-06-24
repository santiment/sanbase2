defmodule Sanbase.Repo.Migrations.CreateYearlyPlans do
  use Ecto.Migration

  alias Sanbase.Pricing.Plan.AccessSeed

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, access) VALUES
      (6, 'ESSENTIAL', 1, #{calc_yearly_price(11900)}, 'USD', 'year', '#{
      AccessSeed.essential() |> Jason.encode!()
    }'),
      (7, 'PRO', 1, #{calc_yearly_price(35900)}, 'USD', 'year', '#{
      AccessSeed.pro() |> Jason.encode!()
    }'),
      (8, 'PREMIUM', 1, #{calc_yearly_price(71900)}, 'USD', 'year', '#{
      AccessSeed.premium() |> Jason.encode!()
    }'),
      (9, 'CUSTOM', 1, 0, 'USD', 'year', '#{AccessSeed.premium() |> Jason.encode!()}')
    """)
  end

  def down do
    :ok
  end

  defp calc_yearly_price(monthly_price) do
    (monthly_price * 12 * 0.9) |> round()
  end
end
