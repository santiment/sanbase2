defmodule Sanbase.Repo.Migrations.CreateYearlyPlans do
  @moduledoc false
  use Ecto.Migration

  alias Sanbase.Billing.Plan.AccessChecker

  def up do
    execute("""
    INSERT INTO plans (id, name, product_id, amount, currency, interval, access) VALUES
      (6, 'ESSENTIAL', 1, #{calc_yearly_price(11_900)}, 'USD', 'year', '#{Jason.encode!(AccessChecker.essential())}'),
      (7, 'PRO', 1, #{calc_yearly_price(35_900)}, 'USD', 'year', '#{Jason.encode!(AccessChecker.pro())}'),
      (8, 'PREMIUM', 1, #{calc_yearly_price(71_900)}, 'USD', 'year', '#{Jason.encode!(AccessChecker.premium())}'),
      (9, 'CUSTOM', 1, 0, 'USD', 'year', '#{Jason.encode!(AccessChecker.premium())}')
    """)
  end

  def down do
    :ok
  end

  defp calc_yearly_price(monthly_price) do
    round(monthly_price * 12 * 0.9)
  end
end
