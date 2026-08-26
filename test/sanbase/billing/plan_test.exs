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

  describe "#api_call_limits" do
    test "standard SanAPI plans answer from the restrictions maps" do
      assert Plan.api_call_limits(%Plan{name: "PRO", product_id: 1}) ==
               %{month: 600_000, hour: 30_000, minute: 600}

      assert Plan.api_call_limits(%Plan{name: "FREE", product_id: 1}) ==
               %{month: 1000, hour: 500, minute: 100}

      assert Plan.api_call_limits(%Plan{name: "BUSINESS_MAX", product_id: 1}) ==
               %{month: 1_200_000, hour: 60_000, minute: 1200}

      assert Plan.api_call_limits(%Plan{name: "INSTITUTIONAL", product_id: 1}) ==
               %{month: 50_000, hour: 30_000, minute: 600}

      assert Plan.api_call_limits(%Plan{name: "ENTERPRISE", product_id: 1}) ==
               %{month: 300_000, hour: 60_000, minute: 1200}
    end

    test "ESSENTIAL answers as BASIC, the plan it is metered as" do
      assert Plan.api_call_limits(%Plan{name: "ESSENTIAL", product_id: 1}) ==
               %{month: 300_000, hour: 20_000, minute: 300}
    end

    test "standard Sanbase plans answer from the restrictions maps" do
      assert Plan.api_call_limits(%Plan{name: "PRO", product_id: 2}) ==
               %{month: 5000, hour: 1000, minute: 100}
    end

    test "plans with no restrictions entry answer nil" do
      # Sanbase FREE means no subscription, so its users are metered as sanapi_free
      assert Plan.api_call_limits(%Plan{name: "FREE", product_id: 2}) == nil
      # the CUSTOM rung has no published numbers - each contract sets its own
      assert Plan.api_call_limits(%Plan{name: "CUSTOM", product_id: 1}) == nil
      assert Plan.api_call_limits(%Plan{name: "RETIRED_ENTERPRISE_BASIC", product_id: 1}) == nil
    end

    test "BUNDLE answers nil - the numbers are per-customer" do
      assert Plan.api_call_limits(%Plan{name: "BUNDLE", product_id: 1}) == nil
    end

    test "CUSTOM_* plans answer from their embedded restrictions" do
      restrictions = %Plan.CustomPlan.Restrictions{
        api_call_limits: %{"month" => 1_000_000, "hour" => 50_000, "minute" => 1000}
      }

      plan = %Plan{name: "CUSTOM_ACME", product_id: 1, restrictions: restrictions}

      assert Plan.api_call_limits(plan) == %{month: 1_000_000, hour: 50_000, minute: 1000}
    end

    test "CUSTOM_* plans sold without a ceiling answer nil" do
      restrictions = %Plan.CustomPlan.Restrictions{api_call_limits: %{"has_limits" => false}}
      plan = %Plan{name: "CUSTOM_ACME", product_id: 1, restrictions: restrictions}

      assert Plan.api_call_limits(plan) == nil
    end
  end
end
