defmodule Sanbase.BillingTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Billing

  setup do
    plans = Sanbase.Billing.TestSeed.seed_products_and_plans()
    %{user: insert(:user), plans: plans}
  end

  describe "san_credit_balance/1" do
    test "is zero for a user without a Stripe customer", %{user: user} do
      assert user.stripe_customer_id == nil
      assert Billing.san_credit_balance(user) === 0.0
    end
  end

  describe "eligible_for_sanbase_trial?/1" do
    test "returns true when user has no sanbase subscriptions", %{user: user} do
      assert Billing.eligible_for_sanbase_trial?(user.id)
    end

    test "returns false when user already has a sanbase subscription", %{user: user} do
      insert(:subscription_pro_sanbase, user: user)
      refute Billing.eligible_for_sanbase_trial?(user.id)
    end
  end

  describe "trial_plan?/1" do
    test "Sanbase PRO, monthly and yearly, is trialled", %{plans: plans} do
      assert Billing.trial_plan?(plans.plan_pro_sanbase)
      assert Billing.trial_plan?(plans.plan_pro_sanbase_yearly)
    end

    test "no other Sanbase plan is trialled", %{plans: plans} do
      for plan <- [
            plans.plan_free_sanbase,
            plans.plan_basic_sanbase,
            plans.plan_pro_plus_sanbase,
            plans.plan_max_sanbase
          ] do
        refute Billing.trial_plan?(plan), "#{plan.name} must not be trialled"
      end
    end

    test "the standard SanAPI plans below Business are trialled", %{plans: plans} do
      assert Billing.trial_plan?(plans.plan_essential)
      assert Billing.trial_plan?(plans.plan_pro)
      assert Billing.trial_plan?(plans.plan_pro_yearly)
    end

    test "FREE and every SanAPI plan above PRO are not trialled", %{plans: plans} do
      for plan <- [
            plans.plan_free,
            plans.plan_business_pro_monthly,
            plans.plan_business_max_yearly,
            plans.plan_custom,
            api_plan("PREMIUM"),
            api_plan("INSTITUTIONAL"),
            api_plan("ENTERPRISE"),
            api_plan("CUSTOM_ACME"),
            api_plan("BUNDLE"),
            api_plan("SOME_FUTURE_PLAN")
          ] do
        refute Billing.trial_plan?(plan), "#{plan.name} must not be trialled"
      end
    end
  end

  defp api_plan(name) do
    %Sanbase.Billing.Plan{product_id: Sanbase.Billing.Product.product_api(), name: name}
  end
end
