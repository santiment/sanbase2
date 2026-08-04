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

  @bundle_plan "BUNDLE"
  @products ["SANAPI", "SANBASE"]
  @item {:metric, "price_usd"}

  # {label, fun} pairs where fun takes (plan_name, product) and reaches exactly
  # one dispatch site.
  defp bundle_entry_points do
    [
      {:get_available_metrics_for_plan,
       &AccessChecker.get_available_metrics_for_plan(&1, &2, :all)},
      # The quota functions take the product-prefixed, downcased form that is
      # stored in api_call_limits.api_calls_limit_plan.
      {:plan_to_api_call_limits, &ApiCallLimit.plan_to_api_call_limits(acl_plan(&2, &1))},
      {:plan_to_response_size_limits,
       &ApiCallLimit.plan_to_response_size_limits(acl_plan(&2, &1))}
    ]
  end

  # Entry points that have a real bundle implementation, and so are asserted
  # directly rather than through the "must raise" list above. When
  # bundle_entry_points/0 is empty, task BA is complete.
  describe "implemented bundle entry points" do
    test "plan_has_access? answers from the entitlement it is handed" do
      entitlement = bundle_entitlement()

      for product <- @products do
        assert AccessChecker.plan_has_access?(
                 {:metric, "price_usd"},
                 product,
                 @bundle_plan,
                 entitlement
               )

        refute AccessChecker.plan_has_access?(
                 {:metric, "mvrv_usd"},
                 product,
                 @bundle_plan,
                 entitlement
               )
      end
    end

    test "plan_has_access? refuses to answer without an entitlement" do
      # Not NotImplementedError - the path exists, the input is missing. Falling
      # back to the standard ladder here would silently under-deliver.
      for product <- @products do
        assert_raise Bundle.MissingEntitlementError, fn ->
          AccessChecker.plan_has_access?(@item, product, @bundle_plan)
        end
      end
    end

    test "plan_has_limits? says a bundle always has limits" do
      for product <- @products do
        assert ApiCallLimit.plan_has_limits?(acl_plan(product, @bundle_plan))
      end
    end

    test "the data windows come from the entitlement" do
      # One window for the whole entitlement, not one per metric (§5.7). The
      # requested item is passed but deliberately not consulted.
      entitlement = %{
        bundle_entitlement()
        | historical_data_in_days: 1095,
          realtime_data_cut_off_in_days: 2
      }

      for product <- @products, item <- [@item, {:query, :get_trending_words}] do
        assert AccessChecker.historical_data_in_days(
                 item,
                 product,
                 product,
                 @bundle_plan,
                 entitlement
               ) == 1095

        assert AccessChecker.realtime_data_cut_off_in_days(
                 item,
                 product,
                 product,
                 @bundle_plan,
                 entitlement
               ) == 2
      end
    end

    test "an unrestricted entitlement reports no window at all" do
      # nil history and a 0 cut-off are what every bundle gets today, and both
      # mean "no restriction" downstream.
      entitlement = bundle_entitlement()

      assert AccessChecker.historical_data_in_days(
               @item,
               "SANAPI",
               "SANAPI",
               @bundle_plan,
               entitlement
             ) ==
               nil

      assert AccessChecker.realtime_data_cut_off_in_days(
               @item,
               "SANAPI",
               "SANAPI",
               @bundle_plan,
               entitlement
             ) == 0
    end

    test "the Sanbase-side limits answer as the equivalent standard plan" do
      # Product's answer to §15 Q5: a bundle customer gets what a SanAPI PRO
      # customer with no Sanbase subscription gets. None of these four has a
      # per-package answer, and before Q5 every one of them raised - so a bundle
      # customer opening Sanbase got a 500.
      equivalent = Bundle.equivalent_standard_plan()

      assert SanbaseAccessChecker.alerts_limit(@bundle_plan) ==
               SanbaseAccessChecker.alerts_limit(equivalent)

      for product <- @products do
        assert Authorization.credits_limit(product, @bundle_plan) ==
                 Authorization.credits_limit(product, equivalent)

        assert Authorization.query_executions_limit(product, @bundle_plan) ==
                 Authorization.query_executions_limit(product, equivalent)

        assert Authorization.user_plan_to_dynamic_repo(product, @bundle_plan) ==
                 Authorization.user_plan_to_dynamic_repo(product, equivalent)
      end
    end

    test "query complexity is divided as the equivalent standard plan" do
      # This site runs in Absinthe's document phase rather than through
      # AccessChecker, so the §7.5 inventory missed it and it raised
      # CaseClauseError on the first real bundle request. Pinned here so it cannot
      # be missed again.
      bundle = %Sanbase.Billing.Subscription{plan: %Plan{name: @bundle_plan}}
      pro = %Sanbase.Billing.Subscription{plan: %Plan{name: Bundle.equivalent_standard_plan()}}

      args = %{from: ~U[2026-01-01 00:00:00Z], to: ~U[2026-02-01 00:00:00Z], interval: "1d"}

      assert SanbaseWeb.Graphql.Complexity.from_to_interval(
               args,
               5,
               %{context: %{auth: %{subscription: bundle}}}
             ) ==
               SanbaseWeb.Graphql.Complexity.from_to_interval(
                 args,
                 5,
                 %{context: %{auth: %{subscription: pro}}}
               )
    end

    test "the data windows refuse to answer without an entitlement" do
      for product <- @products do
        assert_raise Bundle.MissingEntitlementError, fn ->
          AccessChecker.historical_data_in_days(@item, product, product, @bundle_plan)
        end

        assert_raise Bundle.MissingEntitlementError, fn ->
          AccessChecker.realtime_data_cut_off_in_days(@item, product, product, @bundle_plan)
        end
      end
    end
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
      assert Plan.type_of_api_call_limit_plan("sanapi_bundle") == :bundle
    end

    test "preserves today's behavior for sanbase custom plans" do
      # The quota code has always matched "sanapi_custom_" specifically. Custom
      # plans can only exist on the API product, so this case is unreachable in
      # practice - but classifying it as :custom would be a behavior change.
      assert Plan.type_of_api_call_limit_plan("sanbase_custom_acme") == :standard
    end

    test "recognises bundles under the sanbase prefix" do
      assert Plan.type_of_api_call_limit_plan("sanbase_bundle") == :bundle
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
          AccessChecker.get_available_metrics_for_plan(@bundle_plan, "SANAPI", :all)
        end

      assert error.message =~ "get_available_metrics_for_plan"
      assert error.message =~ @bundle_plan
    end

    test "Plan.Restrictions.get passes the entitlement down to the bundle path" do
      # Restrictions.get is what the metric and signal resolvers call. It fans
      # out to plan_has_access? and both window functions, so if it drops the
      # entitlement a bundle customer gets a 500 on metric metadata.
      restriction =
        Sanbase.Billing.Plan.Restrictions.get(
          @item,
          "SANAPI",
          "SANAPI",
          @bundle_plan,
          bundle_entitlement()
        )

      assert restriction.is_accessible

      refused =
        Sanbase.Billing.Plan.Restrictions.get(
          {:metric, "mvrv_usd"},
          "SANAPI",
          "SANAPI",
          @bundle_plan,
          bundle_entitlement()
        )

      refute refused.is_accessible
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

  # A minimal valid entitlement: one metric bought, everything else at the
  # defaults every bundle gets today.
  defp bundle_entitlement do
    %Bundle.Entitlement{
      metric_access: %{"accessible" => ["price_usd"]},
      query_access: %{"accessible" => "all"},
      signal_access: %{"accessible" => "all"},
      api_call_limits: %{"month" => 100_000, "hour" => 30_000, "minute" => 600},
      historical_data_in_days: nil,
      realtime_data_cut_off_in_days: 0,
      schema_version: Bundle.Entitlement.current_schema_version()
    }
  end
end
