defmodule Sanbase.Billing.PlanTypeDispatchTest do
  @moduledoc ~s"""
  Proves that every plan-type-aware entry point actually dispatches on
  `Sanbase.Billing.Plan.type/1`, and that no entry point was missed.

  ## Why this test exists

  Bundle plans get their own code path. Existing plans are never modified, only
  branched around. The failure mode of that design is forgetting a branch, and
  the consequences are bad in two different ways:

    * Sites whose `case` has no catch-all raise `CaseClauseError` - a 500 with a
      message that names neither the plan nor the feature.
    * Sites that *do* have a catch-all are worse: they silently answer as if the
      customer were on the standard ladder. `AccessChecker.plan_has_access?/3`
      falling through would give a paying bundle customer roughly FREE-tier
      access, with no error anywhere.

  Reading the code carefully is not a sufficient guard against that. This test
  is: for every entry point, a bundle plan must reach the bundle path. A missed
  branch returns a standard-ladder value instead of raising, and the test fails
  naming the site.

  ## How to use it while implementing bundles

  `bundle_entry_points/0` is the implementation checklist. Every entry currently
  asserts that the bundle path is reached and raises. As each function gains a
  real implementation, move it out of that list and assert its actual behavior.
  When the list is empty, task BA is complete.

  See `docs/composable-api-plans-handover.md` §7.5 and §7.6.
  """

  use Sanbase.DataCase, async: true

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.AccessMatrix
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.SanbaseAccessChecker
  alias Sanbase.Queries.Authorization

  @bundle_plan "BUNDLE_API"
  @products ["SANAPI", "SANBASE"]
  @item {:metric, "price_usd"}

  # {label, fun} pairs where fun takes (plan_name, product) and reaches exactly
  # one dispatch site.
  defp bundle_entry_points do
    [
      {:plan_has_access?, &AccessChecker.plan_has_access?(@item, &2, &1)},
      {:get_available_metrics_for_plan,
       &AccessChecker.get_available_metrics_for_plan(&1, &2, :all)},
      {:historical_data_in_days, &AccessChecker.historical_data_in_days(@item, &2, &2, &1)},
      {:realtime_data_cut_off_in_days,
       &AccessChecker.realtime_data_cut_off_in_days(@item, &2, &2, &1)},
      {:alerts_limit, fn plan, _product -> SanbaseAccessChecker.alerts_limit(plan) end},
      {:credits_limit, &Authorization.credits_limit(&2, &1)},
      {:query_executions_limit, &Authorization.query_executions_limit(&2, &1)},
      {:user_plan_to_dynamic_repo, &Authorization.user_plan_to_dynamic_repo(&2, &1)},
      # The quota functions take the product-prefixed, downcased form that is
      # stored in api_call_limits.api_calls_limit_plan.
      {:plan_to_api_call_limits, &ApiCallLimit.plan_to_api_call_limits(acl_plan(&2, &1))},
      {:plan_to_response_size_limits,
       &ApiCallLimit.plan_to_response_size_limits(acl_plan(&2, &1))},
      {:plan_has_limits?, &ApiCallLimit.plan_has_limits?(acl_plan(&2, &1))}
    ]
  end

  describe "Plan.type/1" do
    test "classifies the standard ladder as :standard" do
      for plan <- AccessMatrix.standard_plan_names() do
        assert Plan.type(plan) == :standard, "expected #{plan} to be :standard"
      end
    end

    test "classifies exactly CUSTOM as :standard, not :custom" do
      # "CUSTOM" is a rung on the ordinal ladder. Only the CUSTOM_<name> form is
      # a bespoke plan with embedded restrictions.
      assert Plan.type("CUSTOM") == :standard
      assert Plan.type("CUSTOM_ACME") == :custom
    end

    test "classifies BUNDLE names as :bundle" do
      assert Plan.type("BUNDLE") == :bundle
      assert Plan.type("BUNDLE_API") == :bundle
      assert Plan.type("BUNDLE_SANBASE") == :bundle
    end

    test "no existing plan name is accidentally classified as :bundle" do
      # Guards against a future plan name colliding with the bundle prefix.
      for plan <- AccessMatrix.standard_plan_names() ++ ["ESSENTIAL", "CUSTOM_X"] do
        refute Plan.type(plan) == :bundle, "#{plan} must not be classified as :bundle"
      end
    end

    test "is total, so non-binary input does not raise" do
      # The `case plan_name do "CUSTOM_" <> _ -> ...; _ -> ... end` blocks this
      # replaced accepted any term. Adding a guard here would turn existing
      # wrong-argument callers into FunctionClauseError, which is a behavior
      # change. See the note on Plan.type/1.
      assert Plan.type(:pro) == :standard
      assert Plan.type(nil) == :standard
      assert Plan.type({:metric, "price_usd"}) == :standard
      assert Plan.type_of_api_call_limit_plan(nil) == :standard
    end
  end

  describe "Plan.type_of_api_call_limit_plan/1" do
    test "unwraps the product prefix" do
      assert Plan.type_of_api_call_limit_plan("sanapi_pro") == :standard
      assert Plan.type_of_api_call_limit_plan("sanapi_free") == :standard
      assert Plan.type_of_api_call_limit_plan("sanapi_custom_acme") == :custom
      assert Plan.type_of_api_call_limit_plan("sanapi_bundle_api") == :bundle
    end

    test "preserves today's behavior for sanbase custom plans" do
      # The quota code has always matched "sanapi_custom_" specifically. Custom
      # plans can only exist on the API product, so this case is unreachable in
      # practice - but classifying it as :custom would be a behavior change.
      assert Plan.type_of_api_call_limit_plan("sanbase_custom_acme") == :standard
    end

    test "recognises bundles under the sanbase prefix" do
      assert Plan.type_of_api_call_limit_plan("sanbase_bundle_api") == :bundle
    end

    test "exactly sanapi_custom stays :standard" do
      # It is listed in @plans_without_limits and handled before type dispatch.
      assert Plan.type_of_api_call_limit_plan("sanapi_custom") == :standard
    end
  end

  describe "Plan.plan_name/1" do
    test "accepts a BUNDLE plan without raising" do
      # This is the first function any authenticated request hits, via
      # Subscription.plan_name/1 in AuthPlug. Without a BUNDLE clause it raises
      # CaseClauseError before any other code runs.
      assert Plan.plan_name(%Plan{name: @bundle_plan}) == @bundle_plan
    end

    test "still normalises and passes through existing names" do
      assert Plan.plan_name(%Plan{name: "ESSENTIAL"}) == "BASIC"
      assert Plan.plan_name(%Plan{name: "PRO"}) == "PRO"
      assert Plan.plan_name(%Plan{name: "CUSTOM_ACME"}) == "CUSTOM_ACME"
      assert Plan.plan_name(nil) == "FREE"
    end
  end

  describe "bundle dispatch coverage" do
    test "every entry point routes a bundle plan to the bundle path" do
      for {label, fun} <- bundle_entry_points(), product <- @products do
        assert call(fun, @bundle_plan, product) == :dispatched_to_bundle,
               """
               #{label} did not dispatch to the bundle path for product=#{product}.
               Got: #{inspect(call(fun, @bundle_plan, product))}

               Either it returned a standard-ladder answer (a paying bundle
               customer would silently get the wrong access), or it raised
               something other than Bundle.NotImplementedError. Add a `:bundle`
               branch keyed on Plan.type/1.
               """
      end
    end

    test "the failure names the site and the plan" do
      # The point of a dedicated error is diagnosability - a CaseClauseError
      # several frames from the cause is what this replaces.
      error =
        assert_raise Bundle.NotImplementedError, fn ->
          AccessChecker.plan_has_access?(@item, "SANAPI", @bundle_plan)
        end

      assert error.message =~ "plan_has_access?"
      assert error.message =~ @bundle_plan
    end
  end

  describe "existing plans never reach the bundle path" do
    test "no standard plan is routed to the bundle path at any entry point" do
      for plan <- AccessMatrix.standard_plan_names(),
          {label, fun} <- bundle_entry_points(),
          product <- @products do
        refute call(fun, plan, product) == :dispatched_to_bundle,
               "#{label} routed the existing plan #{plan} (#{product}) into the bundle path"
      end
    end
  end

  # Returns :dispatched_to_bundle, {:returned, value} or {:raised, module}.
  #
  # Exceptions other than Bundle.NotImplementedError are returned rather than
  # re-raised: several functions have no clause for some valid plan names
  # (PREMIUM is the live example) and raise CaseClauseError today. That is
  # pre-existing behavior, pinned by the access-matrix fixture, and not this
  # test's concern.
  defp call(fun, plan_name, product) do
    {:returned, fun.(plan_name, product)}
  rescue
    Bundle.NotImplementedError -> :dispatched_to_bundle
    error -> {:raised, error.__struct__}
  end

  defp acl_plan(product, plan_name), do: String.downcase("#{product}_#{plan_name}")
end
