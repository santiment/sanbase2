defmodule Sanbase.Billing.PromoTrialTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup context do
    user = insert(:user, stripe_customer_id: "cus_test_promo")
    Map.put(context, :user, user)
  end

  describe "create_promo_trial/1 cancels at trial end" do
    setup_with_mocks(
      [
        {StripeApi, [:passthrough],
         [
           create_subscription: fn args ->
             send(self(), {:stripe_create_subscription, args})
             StripeApiTestResponse.create_subscription_resp(status: "trialing")
           end
         ]}
      ],
      context
    ) do
      {:ok, context}
    end

    test "passes cancel_at == trial_end to Stripe for list-of-plans variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [plan.id],
                 trial_days: 14
               })

      assert_receive {:stripe_create_subscription, args}
      assert is_integer(args.trial_end)
      assert args.cancel_at == args.trial_end
      assert args.customer == "cus_test_promo"
    end

    test "passes cancel_at == trial_end to Stripe for single plan_id variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, _subscription} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plan_id: plan.id,
                 trial_days: 7
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end
    end

    test "string-keyed params variant also sets cancel_at == trial_end", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 "user_id" => context.user.id,
                 "plans" => [plan.id],
                 "trial_days" => 30
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end
    end

    test "trial_end timestamp roughly matches requested trial_days", context do
      plan = context.plans.plan_pro_sanbase
      trial_days = 14

      {:ok, [_subscription]} =
        PromoTrial.create_promo_trial(%{
          user_id: context.user.id,
          plans: [plan.id],
          trial_days: trial_days
        })

      assert_receive {:stripe_create_subscription, args}
      expected = DateTime.utc_now() |> DateTime.add(trial_days * 24 * 3600, :second)
      delta = abs(args.trial_end - DateTime.to_unix(expected))
      assert delta < 60
    end
  end
end
