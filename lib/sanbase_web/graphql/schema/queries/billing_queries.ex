defmodule SanbaseWeb.Graphql.Schema.BillingQueries do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BillingResolver

  alias SanbaseWeb.Graphql.Middlewares.JWTAuth

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

    @desc ~s"""
    Get upcoming invoice for a subscription
    """
    field :upcoming_invoice, :upcoming_invoice do
      meta(access: :free)

      arg(:subscription_id, non_null(:id))

      middleware(JWTAuth)

      resolve(&BillingResolver.upcoming_invoice/3)
    end

    @desc ~s"""
    Fetch the default customer's card
    """
    field :fetch_default_payment_instrument, :payment_instrument do
      meta(access: :free)

      middleware(JWTAuth)

      resolve(&BillingResolver.fetch_default_payment_instrument/3)
    end

    @desc ~s"""
    Check whether customer is eligible for discount for buying annual subscription
    """
    field :check_annual_discount_eligibility, :annual_discount_eligibility do
      meta(access: :free)

      middleware(JWTAuth)

      resolve(&BillingResolver.check_annual_discount_eligibility/3)
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
    Update the default customer's card
    """
    field :update_default_payment_instrument, :boolean do
      arg(:card_token, non_null(:string))

      middleware(JWTAuth)

      resolve(&BillingResolver.update_default_payment_instrument/3)
    end

    @desc ~s"""
    Delete the default customer's card
    """
    field :delete_default_payment_instrument, :boolean do
      meta(access: :free)

      middleware(JWTAuth)

      resolve(&BillingResolver.delete_default_payment_instrument/3)
    end
  end
end
