defmodule Sanbase.StripeApiTestReponse do
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

  def stripe_product_resp() do
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

  defp create_plan_resp() do
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

  def create_or_update_customer_resp do
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

  def create_subscription_resp do
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
