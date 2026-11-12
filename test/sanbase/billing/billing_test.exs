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

  describe "trial_plan_change_allowed?/2" do
    test "to another trial plan", %{plans: plans} do
      assert Billing.trial_plan_change_allowed?(
               plans.plan_pro_sanbase,
               plans.plan_pro_sanbase_yearly
             )

      assert Billing.trial_plan_change_allowed?(plans.plan_pro, plans.plan_essential)
      assert Billing.trial_plan_change_allowed?(plans.plan_essential, plans.plan_pro)
    end

    test "to the same plan on another interval, even if it is never trialled", %{plans: plans} do
      # A promo trial can be on any paid plan, e.g. Sanbase MAX or SanAPI PREMIUM.
      assert Billing.trial_plan_change_allowed?(
               plans.plan_business_max_monthly,
               plans.plan_business_max_yearly
             )

      premium_month = %{api_plan("PREMIUM") | interval: "month"}
      premium_year = %{api_plan("PREMIUM") | interval: "year"}
      assert Billing.trial_plan_change_allowed?(premium_month, premium_year)
    end

    test "down to a lower plan of the same product", %{plans: plans} do
      assert Billing.trial_plan_change_allowed?(plans.plan_pro_sanbase, plans.plan_basic_sanbase)

      assert Billing.trial_plan_change_allowed?(
               plans.plan_max_sanbase,
               plans.plan_pro_plus_sanbase
             )

      assert Billing.trial_plan_change_allowed?(
               plans.plan_business_max_monthly,
               plans.plan_business_pro_monthly
             )
    end

    test "never up to a plan that is not trialled", %{plans: plans} do
      for {from, to} <- [
            {plans.plan_pro_sanbase, plans.plan_pro_plus_sanbase},
            {plans.plan_pro_sanbase, plans.plan_max_sanbase},
            {plans.plan_pro_plus_sanbase, plans.plan_max_sanbase},
            {plans.plan_pro, plans.plan_business_pro_monthly},
            {plans.plan_pro, plans.plan_business_max_monthly},
            {plans.plan_business_pro_monthly, plans.plan_business_max_monthly}
          ] do
        refute Billing.trial_plan_change_allowed?(from, to), "#{from.name} -> #{to.name}"
      end
    end

    test "never to an unranked plan, whatever it costs", %{plans: plans} do
      # The legacy CUSTOM plan is $0 but gives premium access.
      for to <- [
            plans.plan_custom,
            api_plan("PREMIUM"),
            api_plan("INSTITUTIONAL"),
            api_plan("ENTERPRISE"),
            api_plan("CUSTOM_ACME")
          ] do
        refute Billing.trial_plan_change_allowed?(plans.plan_business_max_monthly, to), to.name
      end
    end

    test "never to another product", %{plans: plans} do
      refute Billing.trial_plan_change_allowed?(plans.plan_max_sanbase, plans.plan_free)
      refute Billing.trial_plan_change_allowed?(plans.plan_pro_sanbase, plans.plan_pro)

      refute Billing.trial_plan_change_allowed?(
               plans.plan_business_max_monthly,
               plans.plan_basic_sanbase
             )
    end
  end

  defp api_plan(name) do
    %Sanbase.Billing.Plan{product_id: Sanbase.Billing.Product.product_api(), name: name}
  end
end
