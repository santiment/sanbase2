defmodule Sanbase.BillingTest do
  use Sanbase.DataCase

  import Sanbase.Factory

  alias Sanbase.Billing

  setup do
    plans = Sanbase.Billing.TestSeed.seed_products_and_plans()
    %{user: insert(:user), plans: plans}
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

  describe "eligible_for_sanbase_trial?/2" do
    test "returns true for PRO plan when user has no sanbase subscriptions", %{
      user: user,
      plans: plans
    } do
      assert Billing.eligible_for_sanbase_trial?(user.id, plans.plan_pro_sanbase)
    end

    test "returns false for MAX plan even when user has no sanbase subscriptions", %{
      user: user,
      plans: plans
    } do
      refute Billing.eligible_for_sanbase_trial?(user.id, plans.plan_max_sanbase)
    end

    test "returns false for PRO_PLUS plan even when user has no sanbase subscriptions", %{
      user: user,
      plans: plans
    } do
      refute Billing.eligible_for_sanbase_trial?(user.id, plans.plan_pro_plus_sanbase)
    end

    test "returns false for PRO plan when user already has a sanbase subscription", %{
      user: user,
      plans: plans
    } do
      insert(:subscription_pro_sanbase, user: user)
      refute Billing.eligible_for_sanbase_trial?(user.id, plans.plan_pro_sanbase)
    end
  end
end
