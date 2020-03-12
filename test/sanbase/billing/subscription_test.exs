defmodule Sanbase.Billing.SubscriptionTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.{Subscription, Plan.AccessChecker}

  setup do
    %{user: insert(:user)}
  end

  describe "#is_restricted?" do
    test "network_growth and daily_active_deposits are restricted" do
      assert AccessChecker.is_restricted?({:query, :network_growth})
      assert AccessChecker.is_restricted?({:query, :daily_active_deposits})
    end

    test "all_projects and history_price are not restricted" do
      refute AccessChecker.is_restricted?({:query, :all_projects})
      refute AccessChecker.is_restricted?({:query, :history_price})
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

  describe "#cancel_about_to_expire_trials" do
    test "cancel when ~2 hours before trial expires and user has no CC", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: nil}} end},
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        subscription =
          insert(:subscription_pro_sanbase,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        insert(:sign_up_trial,
          user_id: context.user.id,
          subscription: subscription
        )

        Subscription.cancel_about_to_expire_trials()

        assert_called(Sanbase.MandrillApi.send("trial-finished-without-card", :_, :_, :_))
      end
    end

    test "doesn't cancel when user has CC", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         retrieve_customer: fn _ -> {:ok, %Stripe.Customer{default_source: "card"}} end},
        {Sanbase.StripeApi, [],
         delete_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "123"}} end},
        {Sanbase.MandrillApi, [:passthrough],
         send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ]) do
        subscription =
          insert(:subscription_pro_sanbase,
            user: context.user,
            status: "trialing",
            trial_end: Timex.shift(Timex.now(), hours: 1)
          )

        insert(:sign_up_trial,
          user_id: context.user.id,
          subscription: subscription
        )

        Subscription.cancel_about_to_expire_trials()

        refute called(Sanbase.MandrillApi.send("trial-finished-without-card", :_, :_, :_))
      end
    end
  end
end
