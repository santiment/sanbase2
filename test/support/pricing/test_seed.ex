defmodule Sanbase.Pricing.TestSeed do
  import Sanbase.Factory

  def seed_products_and_plans() do
    product = insert(:product)

    %{
      product: product,
      plan_free: insert(:plan_free, product: product),
      plan_essential: insert(:plan_essential, product: product),
      plan_pro: insert(:plan_pro, product: product),
      plan_premium: insert(:plan_premium, product: product),
      plan_custom: insert(:plan_custom, product: product),
      plan_essential_yearly: insert(:plan_essential_yearly, product: product),
      plan_pro_yearly: insert(:plan_pro_yearly, product: product),
      plan_premium_yearly: insert(:plan_premium_yearly, product: product),
      plan_custom_yearly: insert(:plan_custom_yearly, product: product)
    }
  end
end
