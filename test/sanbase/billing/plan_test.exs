defmodule Sanbase.Billing.PlanTest do
  use Sanbase.DataCase, async: false

  import Mock

  alias Sanbase.Billing.{Plan, Product}
  alias Sanbase.Billing.TestSeed
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  setup do
    plans = TestSeed.seed_products_and_plans()

    {
      :ok,
      plans: plans
    }
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
        create_plan: fn _ -> StripeApiTestResponse.create_plan_resp() end do
        product_api = context.product_api
        product_api |> Product.changeset(%{stripe_id: "stripe_id"}) |> Repo.update!()
        {:ok, plan} = Plan.maybe_create_plan_in_stripe(context.plans.plan_pro)
        assert plan.stripe_id != nil
      end
    end
  end
end
