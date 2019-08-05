defmodule Sanbase.Billing.TestSeed do
  import Sanbase.Factory

  @key :product_and_plans_map_for_tests

  def seed_products_and_plans() do
    case Sanbase.Repo.get(Sanbase.Billing.Product, 1) do
      nil ->
        product = insert(:product_api)
        product_sanbase = insert(:product_sanbase)
        product_sheets = insert(:product_sheets)

        data = %{
          product: product,
          plan_free: insert(:plan_free, product: product),
          plan_essential: insert(:plan_essential, product: product),
          plan_pro: insert(:plan_pro, product: product),
          plan_premium: insert(:plan_premium, product: product),
          plan_custom: insert(:plan_custom, product: product),
          plan_essential_yearly: insert(:plan_essential_yearly, product: product),
          plan_pro_yearly: insert(:plan_pro_yearly, product: product),
          plan_premium_yearly: insert(:plan_premium_yearly, product: product),
          plan_custom_yearly: insert(:plan_custom_yearly, product: product),
          plan_free_sanbase: insert(:plan_free_sanbase, product: product_sanbase),
          plan_basic_sanbase: insert(:plan_basic_sanbase, product: product_sanbase),
          plan_pro_sanbase: insert(:plan_pro_sanbase, product: product_sanbase),
          plan_free_sheets: insert(:plan_free_sheets, product: product_sheets),
          plan_basic_sheets: insert(:plan_basic_sheets, product: product_sheets),
          plan_pro_sheets: insert(:plan_pro_sheets, product: product_sheets)
        }

        :persistent_term.put(@key, data)

        data

      _ ->
        :persistent_term.get(@key)
    end
  end
end
