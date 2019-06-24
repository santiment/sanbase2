defmodule Sanbase.Pricing.PlanTest do
  use Sanbase.DataCase, async: false

  import Mock

  alias Sanbase.Pricing.{Plan, Product}
  alias Sanbase.Pricing.TestSeed
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestReponse

  setup do
    plans = TestSeed.seed_products_and_plans()

    {
      :ok,
      plans: plans
    }
  end

  describe "#plans_with_metric" do
    test "with standart query - returns all plans" do
      assert Plan.plans_with_metric("network_growth") == [
               "FREE",
               "ESSENTIAL",
               "PRO",
               "PREMIUM",
               "CUSTOM"
             ]
    end

    test "with advanced query - returns only plans with advanced queries" do
      assert Plan.plans_with_metric("mvrv_ratio") == ["PRO", "PREMIUM", "CUSTOM"]
    end
  end

  describe "#maybe_create_plan_in_stripe" do
    test "with plan with stripe_id - returns the plan", context do
      plan =
        context.plans.plan_pro
        |> Plan.changeset(%{stripe_id: "stripe_id"})
        |> Repo.update!()

      assert Plan.maybe_create_plan_in_stripe(plan) == {:ok, plan}
    end

    test "with plan without stripe_id - creates plan in stripe and updates local plan", context do
      with_mock StripeApi,
        create_plan: fn _ -> StripeApiTestReponse.create_plan_resp() end do
        product = context.plans.product
        product |> Product.changeset(%{stripe_id: "stripe_id"}) |> Repo.update!()
        {:ok, plan} = Plan.maybe_create_plan_in_stripe(context.plans.plan_pro)
        assert plan.stripe_id != nil
      end
    end
  end
end
