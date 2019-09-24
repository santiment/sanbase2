defmodule SanbaseWeb.Graphql.Schema.BillingQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BillingResolver

  alias SanbaseWeb.Graphql.Middlewares.{
    JWTAuth
  }

  import_types(SanbaseWeb.Graphql.Schema.BillingTypes)

  object :billing_queries do
    @desc ~s"""
    List available products with corresponding subscription plans.
    """
    field :products_with_plans, list_of(:product) do
      meta(access: :free)

      resolve(&BillingResolver.products_with_plans/3)
    end

    @desc ~s"""
    List all user invoice payments.
    """
    field :payments, list_of(:payments) do
      meta(access: :free)

      middleware(JWTAuth)

      resolve(&BillingResolver.payments/3)
    end

    @desc ~s"""
    Check coupon validity and parameters
    """
    field :get_coupon, :coupon do
      meta(access: :free)

      arg(:coupon, non_null(:string))

      resolve(&BillingResolver.get_coupon/3)
    end
  end

  object :billing_mutations do
    @desc ~s"""
    Subscribe logged in user to a chosen plan.
    Some plans have free trial and doesn't need credit card.
      * `card_token` is an id returned by Stripe upon filling card information.
      * `coupon` is coupon code id giving some percentage off on the price.
    """
    field :subscribe, :subscription_plan do
      arg(:plan_id, non_null(:integer))
      arg(:card_token, :string, default_value: nil)
      arg(:coupon, :string, default_value: nil)

      middleware(JWTAuth)

      resolve(&BillingResolver.subscribe/3)
    end

    @desc ~s"""
    Upgrade/Downgrade a subscription to another plan using existing card information.
    """
    field :update_subscription, :subscription_plan do
      arg(:subscription_id, non_null(:integer))
      arg(:plan_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&BillingResolver.update_subscription/3)
    end

    @desc ~s"""
    Request cancelling a subscription. Subscription won't be deactivated immediately but
    will be active until the current subscription period ends.
    """
    field :cancel_subscription, :subscription_cancellation do
      arg(:subscription_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&BillingResolver.cancel_subscription/3)
    end

    @desc ~s"""
    Request subscription for renewal. Subscription that is cancelled but has not reached
    end of the current period can be renewed.
    """
    field :renew_cancelled_subscription, :subscription_plan do
      arg(:subscription_id, non_null(:integer))

      middleware(JWTAuth)

      resolve(&BillingResolver.renew_cancelled_subscription/3)
    end

    @desc ~s"""
    Request a discount code for all sanbase products.
    """
    field :send_promo_coupon, :send_coupon_success do
      arg(:email, non_null(:string))
      arg(:message, :string)
      arg(:lang, :promo_email_lang_enum)

      resolve(&BillingResolver.send_promo_coupon/3)
    end
  end
end
