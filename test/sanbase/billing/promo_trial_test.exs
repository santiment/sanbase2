defmodule Sanbase.Billing.PromoTrialTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.Subscription.PromoTrial
  alias Sanbase.Repo
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

    test "passes cancel_at 60s before trial_end for list-of-plans variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [plan.id],
                 trial_days: 14
               })

      assert_receive {:stripe_create_subscription, args}
      assert is_integer(args.trial_end)
      assert args.cancel_at == args.trial_end - 60
      assert args.customer == "cus_test_promo"

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 14
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "passes cancel_at 60s before trial_end for single plan_id variant", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, _subscription} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plan_id: plan.id,
                 trial_days: 7
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end - 60

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 7
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "string-keyed params variant also sets cancel_at 60s before trial_end", context do
      plan = context.plans.plan_pro_sanbase

      assert {:ok, [_subscription]} =
               PromoTrial.create_promo_trial(%{
                 "user_id" => context.user.id,
                 "plans" => [plan.id],
                 "trial_days" => 30
               })

      assert_receive {:stripe_create_subscription, args}
      assert args.cancel_at == args.trial_end - 60

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 30
      assert promo_trial.plans == ["Sanbase by Santiment / PRO (month)"]
    end

    test "persists one promo_trials row for multiple plans", context do
      sanbase_plan = context.plans.plan_pro_sanbase
      api_plan = context.plans.plan_pro

      assert {:ok, subscriptions} =
               PromoTrial.create_promo_trial(%{
                 user_id: context.user.id,
                 plans: [sanbase_plan.id, api_plan.id],
                 trial_days: 14
               })

      assert length(subscriptions) == 2
      assert Repo.aggregate(PromoTrial, :count, :id) == 1

      promo_trial = Repo.get_by(PromoTrial, user_id: context.user.id)
      assert promo_trial.trial_days == 14
      assert length(promo_trial.plans) == 2
      assert "Sanbase by Santiment / PRO (month)" in promo_trial.plans
      assert "Sanapi by Santiment / PRO (month)" in promo_trial.plans
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
