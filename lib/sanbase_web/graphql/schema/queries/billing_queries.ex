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
  end

  object :billing_mutations do
    @desc ~s"""
    Subscribe logged in user to a chosen plan using card_token retuned by Stripe on filling
    card information.
    """
    field :subscribe, :subscription_plan do
      arg(:card_token, non_null(:string))
      arg(:plan_id, non_null(:integer))
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
  end
end
