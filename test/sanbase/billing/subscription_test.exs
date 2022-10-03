defmodule Sanbase.Billing.SubscriptionTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.{Subscription, Plan.AccessChecker, Plan}
  alias Sanbase.StripeApiTestResponse
  alias Sanbase.StripeApi

  setup do
    %{user: insert(:user)}
  end

  describe "#sync_subscription_with_stripe" do
    setup(context) do
      stripe_base_subscription =
        StripeApiTestResponse.create_subscription_resp(stripe_id: "test stripe id") |> elem(1)

      stripe_subscription =
        stripe_base_subscription
        |> Map.merge(%{
          status: "trialing",
          trial_end: Timex.now() |> DateTime.to_unix()
        })

      {:ok,
       stripe_subscription: stripe_subscription,
       db_subscription:
         insert(:subscription_pro_sanbase, user: context.user, stripe_id: "test stripe id")}
    end

    test "copy fields from existing Stripe subscription", context do
      Subscription.sync_subscription_with_stripe(
        context.stripe_subscription,
        context.db_subscription
      )

      subscription = Subscription.by_id(context.db_subscription.id)
      assert subscription.status == :trialing

      assert subscription.trial_end ==
               context.stripe_subscription.trial_end |> DateTime.from_unix!()

      assert subscription.plan_id == Plan.by_stripe_id(context.stripe_subscription.plan.id).id
      assert subscription.cancel_at_period_end == context.stripe_subscription.cancel_at_period_end

      assert subscription.current_period_end ==
               context.stripe_subscription.current_period_end |> DateTime.from_unix!()
    end

    test "retrieve Stripe subscription and copy fields", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [retrieve_subscription: fn _ -> {:ok, context.stripe_subscription} end]}
      ]) do
        Subscription.sync_subscription_with_stripe(context.db_subscription)
        subscription = Subscription.by_id(context.db_subscription.id)
        assert subscription.status == :trialing

        assert subscription.trial_end ==
                 context.stripe_subscription.trial_end |> DateTime.from_unix!()

        assert subscription.plan_id == Plan.by_stripe_id(context.stripe_subscription.plan.id).id

        assert subscription.cancel_at_period_end ==
                 context.stripe_subscription.cancel_at_period_end

        assert subscription.current_period_end ==
                 context.stripe_subscription.current_period_end |> DateTime.from_unix!()
      end
    end

    test "when there is no stripe_id, do nothing", context do
      db_subscription = context.db_subscription |> Map.put(:stripe_id, nil)
      assert Subscription.sync_subscription_with_stripe(db_subscription) == :ok
    end
  end

  describe "#is_restricted?" do
    test "network_growth and daily_active_deposits are restricted" do
      assert AccessChecker.is_restricted?("FREE", "SANAPI", {:query, :network_growth})
      assert AccessChecker.is_restricted?("FREE", "SANAPI", {:query, :daily_active_deposits})
    end

    test "all_projects and history_price are not restricted" do
      refute AccessChecker.is_restricted?("FREE", "SANAPI", {:query, :all_projects})
      refute AccessChecker.is_restricted?("FREE", "SANAPI", {:query, :history_price})
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

      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription.plan.id == context.plans.plan_essential.id
    end

    test "when there isn't - return nil", context do
      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription == nil
    end

    test "only active subscriptions", context do
      insert(:subscription_essential,
        user: context.user,
        cancel_at_period_end: true,
        status: "canceled"
      )

      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription == nil
    end
  end
end
