defmodule Sanbase.Billing.TestSeed do
  import Sanbase.Factory

  @key :product_and_plans_map_for_tests

  def seed_products_and_plans() do
    ets_table = Sanbase.TestSetupService.get_ets_table_name()

    case Sanbase.Repo.get(Sanbase.Billing.Product, 1) do
      nil ->
        product_api = insert(:product_api)
        product_sanbase = insert(:product_sanbase)
        product_sandata = insert(:product_sandata)

        data = %{
          product_api: product_api,
          product_sanbase: product_sanbase,
          product_sandata: product_sandata,
          plan_free: insert(:plan_free, product: product_api),
          plan_essential: insert(:plan_essential, product: product_api),
          plan_pro: insert(:plan_pro, product: product_api),
          plan_premium: insert(:plan_premium, product: product_api),
          plan_custom: insert(:plan_custom, product: product_api),
          plan_essential_yearly: insert(:plan_essential_yearly, product: product_api),
          plan_pro_yearly: insert(:plan_pro_yearly, product: product_api),
          plan_premium_yearly: insert(:plan_premium_yearly, product: product_api),
          plan_custom_yearly: insert(:plan_custom_yearly, product: product_api),
          plan_business_pro_monthly: insert(:plan_business_pro_monthly, product: product_api),
          plan_business_pro_yearly: insert(:plan_business_pro_yearly, product: product_api),
          plan_business_max_monthly: insert(:plan_business_max_monthly, product: product_api),
          plan_business_max_yearly: insert(:plan_business_max_yearly, product: product_api),
          plan_free_sanbase: insert(:plan_free_sanbase, product: product_sanbase),
          plan_basic_sanbase: insert(:plan_basic_sanbase, product: product_sanbase),
          plan_pro_sanbase: insert(:plan_pro_sanbase, product: product_sanbase),
          plan_pro_plus_sanbase: insert(:plan_pro_plus_sanbase, product: product_sanbase),
          plan_pro_sanbase_yearly: insert(:plan_pro_sanbase_yearly, product: product_sanbase),
          plan_pro_graphs_factory: insert(:plan_pro_sandata, product: product_sandata),
          plan_pro_70off_sanbase: insert(:plan_pro_70off_sanbase, product: product_sanbase),
          plan_pro_70off_yearly_sanbase:
            insert(:plan_pro_70off_yearly_sanbase, product: product_sanbase),
          plan_pro_plus_70off_sanbase:
            insert(:plan_pro_plus_70off_sanbase, product: product_sanbase),
          plan_pro_plus_70off_yearly_sanbase:
            insert(:plan_pro_plus_70off_yearly_sanbase, product: product_sanbase)
        }

        true = :ets.insert(ets_table, {@key, data})
        data

      _ ->
        [{@key, data}] = :ets.lookup(ets_table, @key)
        data
    end
  end
end
