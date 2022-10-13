defmodule Sanbase.StripeApiTestResponse do
  def create_coupon_resp() do
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

  def create_product_resp() do
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
       name: "SanAPI",
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

  def create_plan_resp() do
    {:ok,
     %Stripe.Plan{
       active: true,
       aggregate_usage: nil,
       amount: 35_900,
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

  def create_or_update_customer_resp do
    {:ok,
     %Stripe.Customer{
       address: nil,
       balance: 0,
       created: 1_611_668_366,
       currency: nil,
       default_source: nil,
       deleted: nil,
       delinquent: false,
       description: "9E8C8A90786C2B6AF4F1804CCAF9E0EB",
       discount: nil,
       email: "non_existing_email@santiment.net",
       id: "cus_nonxistingid",
       invoice_prefix: "1C6F5C94",
       invoice_settings: %{
         custom_fields: nil,
         default_payment_method: nil,
         footer: nil
       },
       livemode: false,
       metadata: %{},
       name: nil,
       next_invoice_sequence: 1,
       object: "customer",
       payment_method: nil,
       phone: nil,
       preferred_locales: [],
       shipping: nil,
       sources: %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         total_count: 0,
         url: "/v1/customers/cus_nonxistingid/sources"
       },
       subscriptions: %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         total_count: 0,
         url: "/v1/customers/cus_nonxistingid/subscriptions"
       },
       tax_exempt: "none",
       tax_ids: %Stripe.List{
         data: [],
         has_more: false,
         object: "list",
         total_count: 0,
         url: "/v1/customers/cus_nonxistingid/tax_ids"
       }
     }}
  end

  def create_subscription_resp(opts \\ []) do
    stripe_id = Keyword.get(opts, :stripe_id, nil)
    stripe_id = stripe_id || "sub_" <> Base.encode16(:crypto.strong_rand_bytes(7))
    status = Keyword.get(opts, :status, "active")
    trial_end = Keyword.get(opts, :trial_end, nil)

    {:ok,
     %Stripe.Subscription{
       application_fee_percent: nil,
       collection_method: "charge_automatically",
       billing_cycle_anchor: 1_558_185_786,
       cancel_at_period_end: false,
       canceled_at: nil,
       created: 1_558_185_786,
       current_period_end: 1_560_864_186,
       current_period_start: 1_558_185_786,
       customer: "cus_nonxistingid",
       days_until_due: nil,
       discount: nil,
       ended_at: nil,
       id: stripe_id,
       items: %Stripe.List{
         data: [
           %Stripe.SubscriptionItem{
             created: 1_558_185_787,
             deleted: nil,
             id: "si_anothernonexistingid",
             metadata: %{},
             object: "subscription_item",
             plan: %Stripe.Plan{
               active: true,
               aggregate_usage: nil,
               amount: 35_900,
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
               product: "prod_nonexistingproduct",
               tiers: nil,
               tiers_mode: nil,
               transform_usage: nil,
               trial_period_days: nil,
               usage_type: "licensed"
             },
             quantity: 1,
             subscription: "sub_nonexistingsub"
           }
         ],
         has_more: false,
         object: "list",
         total_count: 1,
         url: "/v1/subscription_items?subscription=sub_nonexistingsub"
       },
       livemode: false,
       metadata: %{},
       object: "subscription",
       plan: %Stripe.Plan{
         active: true,
         aggregate_usage: nil,
         amount: 35_900,
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
         product: "prod_nonexistingproduct",
         tiers: nil,
         tiers_mode: nil,
         transform_usage: nil,
         trial_period_days: nil,
         usage_type: "licensed"
       },
       quantity: 1,
       start_date: 1_558_185_786,
       status: status,
       tax_rate: nil,
       trial_end: trial_end,
       trial_start: nil
     }}
  end

  def update_subscription_resp(opts \\ []) do
    create_subscription_resp(opts)
  end

  def retrieve_subscription_resp(opts \\ []) do
    create_subscription_resp(opts)
  end

  def delete_subscription_resp(opts \\ []) do
    create_subscription_resp(opts)
  end
end
