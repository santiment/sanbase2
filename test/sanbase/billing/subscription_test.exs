defmodule Sanbase.Billing.SubscriptionTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory

  alias Sanbase.Billing.Subscription

  setup do
    %{user: insert(:user)}
  end

  describe "#is_restricted?" do
    test "network_growth and daily_active_deposits are restricted" do
      assert Subscription.is_restricted?({:query, :network_growth})
      assert Subscription.is_restricted?({:query, :daily_active_deposits})
    end

    test "all_projects and history_price are not restricted" do
      refute Subscription.is_restricted?({:query, :all_projects})
      refute Subscription.is_restricted?({:query, :history_price})
    end
  end

  describe "#user_subscriptions" do
    test "when there are subscriptions - currentUser return list of subscriptions", context do
      insert(:subscription_essential, user: context.user)

      subscription = Subscription.user_subscriptions(context.user) |> hd()
      assert subscription.plan.name == "ESSENTIAL"
    end

    test "when there are no subscriptions - return []", context do
      assert Subscription.user_subscriptions(context.user) == []
    end

    test "only active subscriptions", context do
      insert(:subscription_essential,
        user: context.user,
        cancel_at_period_end: true,
        status: "canceled"
      )

      assert Subscription.user_subscriptions(context.user) == []
    end
  end

  describe "#current_subscription" do
    test "when there is subscription - return it", context do
      insert(:subscription_essential, user: context.user)

      current_subscription = Subscription.current_subscription(context.user, context.product.id)
      assert current_subscription.plan.id == context.plans.plan_essential.id
    end

    test "when there isn't - return nil", context do
      current_subscription = Subscription.current_subscription(context.user, context.product.id)
      assert current_subscription == nil
    end

    test "only active subscriptions", context do
      insert(:subscription_essential,
        user: context.user,
        cancel_at_period_end: true,
        status: "canceled"
      )

      current_subscription = Subscription.current_subscription(context.user, context.product.id)
      assert current_subscription == nil
    end
  end
end
