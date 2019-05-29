defmodule Sanbase.Pricing.StripeFlowTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import Sanbase.DateTimeUtils, only: [from_iso8601!: 1]

  alias Sanbase.Pricing.{Product, Plan}
  alias Sanbase.Pricing.Plan.AccessSeed
  alias Sanbase.Auth.Apikey

  setup_with_mocks([
    {Stripe.Product, [], [create: fn _ -> stripe_product_resp() end]},
    {Stripe.Plan, [], [create: fn _ -> stripe_plan_resp() end]},
    {Stripe.Customer, [], [create: fn _ -> stripe_customer_resp() end]},
    {Stripe.Customer, [], [update: fn _, _ -> stripe_customer_resp() end]},
    {Stripe.Coupon, [], [create: fn _ -> stripe_coupon_resp() end]},
    {Stripe.Subscription, [], [create: fn _ -> stripe_subscription_resp() end]},
    {Sanbase.Clickhouse.MVRV, [], [mvrv_ratio: fn _, _, _, _ -> mvrv_resp() end]},
    {Sanbase.Clickhouse.NetworkGrowth, [],
     [network_growth: fn _, _, _, _ -> network_growth_resp() end]}
  ]) do
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)
    product = create_product()
    plan = create_plan(product, :plan_essential)
    insert(:plan_pro, product: product)
    insert(:plan_premium, product: product)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    {:ok, conn: conn, user: user, product: product, plan: plan, conn_apikey: conn_apikey}
  end

  test "list products with plans", context do
    query = list_products_with_plans_query()

    result =
      context.conn
      |> execute_query(query, "listProductsWithPlans")
      |> hd()

    assert result["name"] == "SanbaseAPI"
    assert length(result["plans"]) == 3
  end

  test "current user subscriptions", context do
    query = subscribe_mutation(context.plan.id)
    execute_mutation(context.conn, query, "subscribe")

    current_user = execute_query(context.conn, current_user_query(), "currentUser")
    subscription = current_user["subscriptions"] |> hd()

    assert subscription["plan"]["name"] == "Essential"
  end

  describe "no subscriptions" do
    test "restricted query", context do
      query = mvrv_query(Timex.shift(Timex.now(), days: -10), Timex.shift(Timex.now(), days: -8))
      result = execute_query(context.conn_apikey, query, "mvrvRatio")

      assert result == [
               %{"datetime" => "2019-01-01T00:00:00Z", "ratio" => 0.1},
               %{"datetime" => "2019-01-02T00:00:00Z", "ratio" => 0.2}
             ]
    end

    test "restricted query with from/to more than 3 months ago", context do
      query = mvrv_query(Timex.shift(Timex.now(), days: -200), Timex.shift(Timex.now(), days: -8))
      result = execute_query(context.conn_apikey, query, "mvrvRatio")

      assert result == [
               %{"datetime" => "2019-01-01T00:00:00Z", "ratio" => 0.1},
               %{"datetime" => "2019-01-02T00:00:00Z", "ratio" => 0.2}
             ]
    end
  end

  describe "subscribed to essential plan" do
    test "with query in plan", context do
      query = subscribe_mutation(context.plan.id)
      execute_mutation(context.conn, query, "subscribe")

      query =
        network_growth_query(
          from_iso8601!("2019-03-01T00:00:00Z"),
          from_iso8601!("2019-03-03T00:00:00Z")
        )

      result = execute_query(context.conn_apikey, query, "networkGrowth")

      assert result == [
               %{"datetime" => "2019-01-01T00:00:00Z", "newAddresses" => 10},
               %{"datetime" => "2019-01-02T00:00:00Z", "newAddresses" => 20}
             ]
    end

    test "with query outside plan", context do
      query = subscribe_mutation(context.plan.id)
      execute_mutation(context.conn, query, "subscribe")

      query =
        mvrv_query(from_iso8601!("2019-03-01T00:00:00Z"), from_iso8601!("2019-03-03T00:00:00Z"))

      error_msg = execute_query_with_error(context.conn_apikey, query, "mvrvRatio")

      assert error_msg == """
             Requested metric mvrv_ratio is not provided by the current subscription plan #{
               context.plan.name
             }.
             Please upgrade to Pro or Premium to get access to mvrv_ratio
             """
    end

    test "with query in plan but outside allowed historical data", context do
      query = subscribe_mutation(context.plan.id)
      execute_mutation(context.conn, query, "subscribe")

      allowed_days = AccessSeed.essential()[:historical_data_in_days]

      from = Timex.shift(Timex.now(), days: -(allowed_days + 1))
      to = Timex.shift(Timex.now(), days: -(allowed_days - 1))
      query = network_growth_query(from, to)
      result = execute_query(context.conn_apikey, query, "networkGrowth")

      assert result == [
               %{"datetime" => "2019-01-01T00:00:00Z", "newAddresses" => 10},
               %{"datetime" => "2019-01-02T00:00:00Z", "newAddresses" => 20}
             ]
    end
  end

  defp mvrv_query(from, to) do
    """
      {
        mvrvRatio(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime,
          ratio
        }
      }
    """
  end

  defp network_growth_query(from, to) do
    """
      {
        networkGrowth(slug: "ethereum", from: "#{from}", to: "#{to}", interval: "1d"){
          datetime,
          newAddresses
        }
      }
    """
  end

  defp current_user_query do
    """
    {
      currentUser {
        subscriptions {
          plan {
            id
            name
            access
            product {
              name
            }
          }
        }
      }
    }
    """
  end

  defp list_products_with_plans_query() do
    """
    {
      listProductsWithPlans {
        name
        plans {
          name
          access
        }
      }
    }
    """
  end

  defp subscribe_mutation(plan_id) do
    """
    mutation {
      subscribe(card_token: "card_token", plan_id: #{plan_id}) {
        plan {
          id
          name
          access
          product {
            name
          }
        }
      }
    }
    """
  end

  defp create_product do
    product = insert(:product)
    {:ok, product} = Product.by_id(product.id)
    product
  end

  defp create_plan(product, plan_type)
       when plan_type in [:plan_essential, :plan_pro, :plan_premium] do
    plan = insert(plan_type, product: product)
    {:ok, plan} = Plan.by_id(plan.id)
    plan
  end

  defp mvrv_resp() do
    {:ok,
     [
       %{ratio: 0.1, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{ratio: 0.2, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end

  defp network_growth_resp() do
    {:ok,
     [
       %{new_addresses: 10, datetime: from_iso8601!("2019-01-01T00:00:00Z")},
       %{new_addresses: 20, datetime: from_iso8601!("2019-01-02T00:00:00Z")}
     ]}
  end

  defp stripe_coupon_resp() do
    {:ok,
     %Stripe.Coupon{
       amount_off: nil,
       created: 1_558_341_692,
       currency: nil,
       deleted: nil,
       duration: "forever",
       duration_in_months: nil,
       id: "61XDdQ9D",
       livemode: false,
       max_redemptions: nil,
       metadata: %{},
       name: nil,
       object: "coupon",
       percent_off: 20.0,
       redeem_by: nil,
       times_redeemed: 0,
       valid: true
     }}
  end

  defp stripe_product_resp() do
    {:ok,
     %Stripe.Product{
       active: true,
       attributes: [],
       caption: nil,
       created: 1_558_173_662,
       deactivate_on: [],
       deleted: nil,
       description: nil,
       id: "prod_F5aWms1Lp2sHe5",
       images: [],
       livemode: false,
       metadata: %{},
       name: "SANapi",
       object: "product",
       package_dimensions: nil,
       shippable: nil,
       statement_descriptor: nil,
       type: "service",
       unit_label: nil,
       updated: 1_558_173_662,
       url: nil
     }}
  end

  defp stripe_plan_resp() do
    {:ok,
     %Stripe.Plan{
       active: true,
       aggregate_usage: nil,
       amount: 35900,
       billing_scheme: "per_unit",
       created: 1_558_178_870,
       currency: "usd",
       deleted: nil,
       id: "plan_F5bv8ZRkhnAnmR",
       interval: "month",
       interval_count: 1,
       livemode: false,
       metadata: %{},
       name: "PRO",
       nickname: nil,
       object: "plan",
       product: "prod_F5aWms1Lp2sHe5",
       tiers: nil,
       tiers_mode: nil,
       transform_usage: nil,
       trial_period_days: nil,
       usage_type: "licensed"
     }}
  end

  defp stripe_customer_resp do
    {:ok,
     %Stripe.Customer{
       account_balance: 0,
       created: 1_558_015_347,
       currency: "usd",
       default_source: "card_1EbSP1CA0hGU8IEVPRxGB0SU",
       deleted: nil,
       delinquent: false,
       description: "tsvetozar.penov@gmail.com",
       discount: nil,
       email: nil,
       id: "cus_F4ty1PY1JIzyfi",
       invoice_prefix: "3AA97AE0",
       invoice_settings: %{
         custom_fields: nil,
         default_payment_method: nil,
         footer: nil
       },
       livemode: false,
       metadata: %{},
       object: "customer",
       shipping: nil,
       sources: %Stripe.List{
         data: [
           %Stripe.Card{
             account: nil,
             address_city: nil,
             address_country: nil,
             address_line1: nil,
             address_line1_check: nil,
             address_line2: nil,
             address_state: nil,
             address_zip: "12345",
             address_zip_check: "pass",
             available_payout_methods: nil,
             brand: "Visa",
             country: "US",
             currency: nil,
             customer: "cus_F4ty1PY1JIzyfi",
             cvc_check: "pass",
             default_for_currency: nil,
             deleted: nil,
             dynamic_last4: nil,
             exp_month: 10,
             exp_year: 2023,
             fingerprint: "hSHi7W7s6frUu26i",
             funding: "credit",
             id: "card_1EbSP1CA0hGU8IEVPRxGB0SU",
             last4: "4242",
             metadata: %{},
             name: nil,
             object: "card",
             recipient: nil,
             tokenization_method: nil
           }
         ],
         has_more: false,
         object: "list",
         total_count: 1,
         url: "/v1/customers/cus_F4ty1PY1JIzyfi/sources"
       },
       subscriptions: %Stripe.List{
         data: [
           %Stripe.Subscription{
             application_fee_percent: nil,
             billing: "charge_automatically",
             billing_cycle_anchor: 1_558_015_628,
             cancel_at_period_end: false,
             canceled_at: nil,
             created: 1_558_015_628,
             current_period_end: 1_560_694_028,
             current_period_start: 1_558_015_628,
             customer: "cus_F4ty1PY1JIzyfi",
             days_until_due: nil,
             discount: nil,
             ended_at: nil,
             id: "sub_F4u2B5At3tmbtV",
             items: %Stripe.List{
               data: [
                 %Stripe.SubscriptionItem{
                   created: 1_558_015_629,
                   deleted: nil,
                   id: "si_F4u27F2cU3a4TM",
                   metadata: %{},
                   object: "subscription_item",
                   plan: %Stripe.Plan{
                     active: true,
                     aggregate_usage: nil,
                     amount: 5000,
                     billing_scheme: "per_unit",
                     created: 1_557_758_525,
                     currency: "usd"
                   },
                   quantity: 1,
                   subscription: "sub_F4u2B5At3tmbtV"
                 }
               ],
               has_more: false,
               object: "list",
               total_count: 1,
               url: "/v1/subscription_items?subscription=sub_F4u2B5At3tmbtV"
             },
             livemode: false,
             metadata: %{},
             object: "subscription",
             plan: %Stripe.Plan{
               active: true,
               aggregate_usage: nil,
               amount: 5000,
               billing_scheme: "per_unit",
               created: 1_557_758_525,
               currency: "usd",
               deleted: nil,
               id: "plan_F3mvutBFg21hoh",
               interval: "month",
               interval_count: 1
             },
             quantity: 1,
             start: 1_558_015_628,
             status: "active",
             tax_percent: nil,
             trial_end: nil,
             trial_start: nil
           }
         ],
         has_more: false,
         object: "list",
         total_count: 1,
         url: "/v1/customers/cus_F4ty1PY1JIzyfi/subscriptions"
       },
       tax_info: nil,
       tax_info_verification: nil
     }}
  end

  defp stripe_subscription_resp do
    {:ok,
     %Stripe.Subscription{
       application_fee_percent: nil,
       billing: "charge_automatically",
       billing_cycle_anchor: 1_558_185_786,
       cancel_at_period_end: false,
       canceled_at: nil,
       created: 1_558_185_786,
       current_period_end: 1_560_864_186,
       current_period_start: 1_558_185_786,
       customer: "cus_F4ty1PY1JIzyfi",
       days_until_due: nil,
       discount: nil,
       ended_at: nil,
       id: "sub_F5dmKstgL3Yq3r",
       items: %Stripe.List{
         data: [
           %Stripe.SubscriptionItem{
             created: 1_558_185_787,
             deleted: nil,
             id: "si_F5dmDhHWlVMFkV",
             metadata: %{},
             object: "subscription_item",
             plan: %Stripe.Plan{
               active: true,
               aggregate_usage: nil,
               amount: 35900,
               billing_scheme: "per_unit",
               created: 1_558_178_870,
               currency: "usd",
               deleted: nil,
               id: "plan_F5bv8ZRkhnAnmR",
               interval: "month",
               interval_count: 1,
               livemode: false,
               metadata: %{},
               name: nil,
               nickname: nil,
               object: "plan",
               product: "prod_F5bvgigFaj5Qqo",
               tiers: nil,
               tiers_mode: nil,
               transform_usage: nil,
               trial_period_days: nil,
               usage_type: "licensed"
             },
             quantity: 1,
             subscription: "sub_F5dmKstgL3Yq3r"
           }
         ],
         has_more: false,
         object: "list",
         total_count: 1,
         url: "/v1/subscription_items?subscription=sub_F5dmKstgL3Yq3r"
       },
       livemode: false,
       metadata: %{},
       object: "subscription",
       plan: %Stripe.Plan{
         active: true,
         aggregate_usage: nil,
         amount: 35900,
         billing_scheme: "per_unit",
         created: 1_558_178_870,
         currency: "usd",
         deleted: nil,
         id: "plan_F5bv8ZRkhnAnmR",
         interval: "month",
         interval_count: 1,
         livemode: false,
         metadata: %{},
         name: nil,
         nickname: nil,
         object: "plan",
         product: "prod_F5bvgigFaj5Qqo",
         tiers: nil,
         tiers_mode: nil,
         transform_usage: nil,
         trial_period_days: nil,
         usage_type: "licensed"
       },
       quantity: 1,
       start: 1_558_185_786,
       status: "active",
       tax_percent: nil,
       trial_end: nil,
       trial_start: nil
     }}
  end
end
