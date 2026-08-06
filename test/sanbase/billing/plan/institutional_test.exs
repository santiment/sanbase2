defmodule Sanbase.Billing.Plan.InstitutionalTest do
  @moduledoc ~s"""
  What the `INSTITUTIONAL` plan grants, and who is allowed to buy it.

  Institutional is the middle column of the new SanAPI offering (§1.1), but it is
  deliberately *not* built out of packages: it is a fixed plan on the standard
  path, so its access and quota are declared in code rather than assembled from
  purchased items. That makes almost everything about it a matter of adding one
  clause to each plan-dependent `case`, and the failure mode of that is a missing
  clause - either a `CaseClauseError` on the first real request, or a catch-all
  quietly answering as if the customer were on FREE.

  `Sanbase.Billing.PlanTypeDispatchTest` and the access-matrix fixture already
  catch a missing clause. This file pins the *values*, because several of them are
  intentionally not what the neighbouring tier gets and would otherwise look like
  mistakes to whoever reads them next:

    * 50,000 calls a month - lower than every other paid SanAPI plan, and lower
      than a single package. Institutional sells breadth and a 3-year history;
      volume is what packages and their add-ons sell (§9).
    * a 3-year history window, where BUSINESS_MAX has no limit at all.
    * full Sanbase, so the Sanbase-side answers are MAX's rather than PRO's - a
      bundle gets PRO's, and that difference is the point.

  See `docs/composable-api-plans-handover.md` §8 task IN.
  """

  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserRole
  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle.Lifecycle
  alias Sanbase.Billing.Plan.SanbaseAccessChecker
  alias Sanbase.Billing.Subscription
  alias Sanbase.Queries.Authorization
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  @plan "INSTITUTIONAL"
  @acl_plan "sanapi_institutional"

  # A metric and a query that a FREE user cannot have in full, so "full SanAPI"
  # is actually being asserted rather than a free-for-all answer.
  @restricted_metric {:metric, "mvrv_usd"}
  @pro_only_query {:query, :miners_balance}

  describe "plan classification" do
    test "is a standard plan, not a bundle" do
      # It shares the offering with BUNDLE commercially and nothing else
      # technically: no items, no entitlement, no multi-item Stripe subscription.
      assert Plan.type(@plan) == :standard
      assert Plan.type_of_api_call_limit_plan(@acl_plan) == :standard
    end

    test "reaches the access layer under its own name" do
      # plan_name/1 is the first function an authenticated request hits. Without a
      # clause it raises CaseClauseError before any other code runs.
      assert Plan.plan_name(%Plan{name: @plan}) == @plan
    end
  end

  describe "SanAPI access" do
    test "grants the metrics and queries a paid API plan grants" do
      assert AccessChecker.plan_has_access?(@restricted_metric, "SANAPI", @plan)
      assert AccessChecker.plan_has_access?(@pro_only_query, "SANAPI", @plan)
    end

    test "history is three years, where BUSINESS_MAX has no limit" do
      # The window is the product's, not an inherited one. BUSINESS_MAX answers nil
      # (unlimited) and BUSINESS_PRO 730 - this sits between them on purpose.
      assert data_windows(@restricted_metric, "SANAPI") == %{history: 3 * 365, cut_off: 0}

      assert AccessChecker.historical_data_in_days(
               @restricted_metric,
               "SANAPI",
               "SANAPI",
               "BUSINESS_MAX"
             ) == nil
    end

    test "the window does not depend on which item is asked about" do
      # One window for the whole plan. A per-item answer would mean the 3-year
      # limit could be missing on whichever item nobody thought to check.
      assert data_windows(@pro_only_query, "SANAPI") == %{history: 3 * 365, cut_off: 0}
    end

    test "realtime data is included" do
      assert data_windows(@restricted_metric, "SANAPI").cut_off == 0
    end

    test "the metric catalog can be browsed by plan name alone" do
      # `getAvailableMetrics(plan: INSTITUTIONAL)` reaches here. A bundle cannot be
      # answered this way - every bundle is named BUNDLE and each allows something
      # different - but Institutional is a fixed plan, so the name is the whole
      # question.
      metrics = AccessChecker.get_available_metrics_for_plan(@plan, "SANAPI", :all)

      assert {:metric, metric} = @restricted_metric
      assert metric in metrics
    end
  end

  describe "Sanbase access" do
    test "answers as MAX, because full Sanbase is part of what was sold" do
      # A bundle answers as PRO here. Institutional includes Sanbase outright, so
      # it gets the top Sanbase tier instead.
      assert SanbaseAccessChecker.alerts_limit(@plan) == SanbaseAccessChecker.alerts_limit("MAX")

      assert SanbaseAccessChecker.can_access_paywalled_insights?(%Subscription{
               plan: %Plan{name: @plan}
             })
    end
  end

  describe "call quota" do
    test "50,000 calls a month - deliberately the lowest of the paid API plans" do
      assert ApiCallLimit.plan_to_api_call_limits(@acl_plan) == %{
               month: 50_000,
               hour: 30_000,
               minute: 600
             }
    end

    test "the burst limits are not scaled down with the month" do
      # The monthly figure is what is being sold; the hour and minute are there to
      # stop a single client saturating the cluster. Throttling an institutional
      # customer harder than a package customer inside their own allowance would
      # be a worse plan for more money.
      assert ApiCallLimit.plan_to_api_call_limits(@acl_plan)
             |> Map.take([:hour, :minute]) ==
               ApiCallLimit.plan_to_api_call_limits("sanapi_pro")
               |> Map.take([:hour, :minute])
    end

    test "has limits at all" do
      # Not on the unlimited list. A flagship plan with no quota row would be
      # discovered as an unmetered customer, not as a bug.
      assert ApiCallLimit.plan_has_limits?(@acl_plan)
    end

    test "response size is capped" do
      assert ApiCallLimit.plan_to_response_size_limits(@acl_plan) == %{month: 50_000}
    end
  end

  describe "Queries and complexity" do
    test "gets the widest table access and the BUSINESS_MAX query allowances" do
      # Everything that is neither metric access nor call volume answers as the
      # top standard tier: these are not dimensions Institutional sells, and
      # inventing separate numbers for each would be a set of values nobody
      # decided.
      for site <- [:repo, :credits, :executions] do
        assert authorization(site, @plan) == authorization(site, "BUSINESS_MAX"),
               "#{site} should answer as BUSINESS_MAX"
      end
    end

    test "query complexity is divided as for BUSINESS_MAX" do
      # This site runs in Absinthe's document phase rather than through
      # AccessChecker, which is how it was missed for bundles and raised
      # CaseClauseError on the first real request.
      args = %{from: ~U[2026-01-01 00:00:00Z], to: ~U[2026-02-01 00:00:00Z], interval: "1d"}

      assert complexity(args, @plan) == complexity(args, "BUSINESS_MAX")
    end
  end

  describe "MCP" do
    test "an Institutional subscriber is MAX tier" do
      # MCP is listed in what Institutional includes, and classify/2 has a
      # catch-all returning :free - so a missing clause here would not raise, it
      # would silently sell MCP and then serve 15 calls a minute.
      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: institutional_plan("month").id,
        status: :active,
        stripe_id: "sub_inst_" <> Ecto.UUID.generate()
      )

      assert Sanbase.MCP.Restrictions.tier_for_user(user) == :max
    end
  end

  describe "who may buy it" do
    setup do
      insert(:role_san_team)
      institutional_plan("month")
      bundle_plan("month")

      %{user: insert(:user, stripe_customer_id: "cus_inst_" <> Ecto.UUID.generate())}
    end

    test "not for sale while the new offering is deactivated", %{user: user} do
      assert {:error, "The Institutional plan is not available for purchase yet"} =
               Lifecycle.ensure_can_subscribe_institutional(user)
    end

    test "a team member can buy it while it is deactivated", %{user: user} do
      # How it gets tested before launch, and the same exemption bundles have.
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

      assert :ok = Lifecycle.ensure_can_subscribe_institutional(user)
    end

    test "for sale once the offering is activated", %{user: user} do
      activate_offering()

      assert :ok = Lifecycle.ensure_can_subscribe_institutional(user)
    end

    test "refused to a customer who already has a bundle", %{user: user} do
      # The rule that has_active_subscriptions/2 cannot enforce: it compares plan
      # ids, so without this the customer ends up with two live SanAPI
      # subscriptions billing at once.
      activate_offering()

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: bundle_plan("month").id,
        status: :active,
        stripe_id: "sub_bundle_" <> Ecto.UUID.generate()
      )

      assert {:error, "You already have an active SanAPI subscription on the new offering"} =
               Lifecycle.ensure_can_subscribe_institutional(user)
    end

    test "allowed while a replaceable legacy subscription is still live", %{user: user} do
      # The legacy subscription is not canceled here. It is canceled with proration
      # by cancel_stale_replaced_subscriptions/0 once the new one is actually live -
      # so a declined first invoice cannot cost the customer the plan they are
      # still paying for.
      activate_offering()

      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: business_pro_plan().id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      assert :ok = Lifecycle.ensure_can_subscribe_institutional(user)
      assert Repo.reload!(legacy).status == :active
    end

    test "subscribe refuses before charging anything", %{user: user} do
      # The gate is only worth having if it runs before Stripe does. If it moved
      # below the charge, the customer would be billed and then told no.
      with_mocks([
        {StripeApi, [:passthrough],
         [
           create_customer_with_card: fn _, _ ->
             {:ok, %Stripe.Customer{id: "cus_never_created"}}
           end,
           create_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "sub_never_created"}} end
         ]}
      ]) do
        assert {:error, %Subscription.Error{message: message}} =
                 Subscription.subscribe(user, institutional_plan("month"), "card_token")

        assert message == "The Institutional plan is not available for purchase yet"

        assert_not_called(StripeApi.create_customer_with_card(:_, :_))
        assert_not_called(StripeApi.create_subscription(:_))
      end
    end
  end

  describe "the plan rows" do
    test "are kept out of the pricing page listing" do
      # Same reason the BUNDLE markers are: the Institutional column is rendered
      # from its own copy, and listing the row would offer subscribe(plan_id:) a
      # plan the pricing page does not drive.
      institutional_plan("month")

      assert {:ok, products} = Plan.product_with_plans()

      refute @plan in Enum.flat_map(products, fn product ->
               Enum.map(product.plans, & &1.name)
             end)
    end

    test "are toggled by the same switch as the bundle rows" do
      # One switch for the whole offering. Two would allow a state where the
      # pricing page shows a column nobody can buy.
      monthly = institutional_plan("month")
      bundle_plan("month")

      assert {:ok, ids} = Sanbase.Billing.Plan.SaleControls.activate_bundle_plans()
      assert monthly.id in ids
      refute Repo.reload!(monthly).is_private
    end
  end

  # --- helpers ---

  # Not `windows/2`: DataCase imports Ecto.Query, which exports a macro by that
  # name, and the clash is a compile error rather than a shadowing warning.
  defp data_windows(item, product) do
    %{
      history: AccessChecker.historical_data_in_days(item, product, product, @plan),
      cut_off: AccessChecker.realtime_data_cut_off_in_days(item, product, product, @plan)
    }
  end

  defp authorization(:repo, plan), do: Authorization.user_plan_to_dynamic_repo("SANAPI", plan)
  defp authorization(:credits, plan), do: Authorization.credits_limit("SANAPI", plan)

  defp authorization(:executions, plan),
    do: Authorization.query_executions_limit("SANAPI", plan)

  defp complexity(args, plan_name) do
    subscription = %Subscription{plan: %Plan{name: plan_name}}

    SanbaseWeb.Graphql.Complexity.from_to_interval(args, 5, %{
      context: %{auth: %{subscription: subscription}}
    })
  end

  defp activate_offering do
    {:ok, _} = Sanbase.Billing.Plan.SaleControls.activate_bundle_plans()
    :ok
  end

  defp institutional_plan(interval), do: new_offering_plan(@plan, interval, 9701)
  defp bundle_plan(interval), do: new_offering_plan("BUNDLE", interval, 9711)

  # The migration seeds these rows against products.id = 1, which does not exist
  # when the test database is migrated - so in tests they have to be created here.
  defp new_offering_plan(name, interval, base_id) do
    product_api_id = Sanbase.Billing.Product.product_api()

    case Repo.get_by(Plan, name: name, interval: interval, product_id: product_api_id) do
      %Plan{} = plan ->
        plan

      nil ->
        id = base_id + if interval == "month", do: 0, else: 1
        Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH #{base_id + 100}")

        insert(:plan_pro,
          id: id,
          name: name,
          product_id: product_api_id,
          interval: interval,
          amount: if(name == @plan, do: 79_900, else: 0),
          is_private: true,
          is_deprecated: false,
          stripe_id: "plan_#{String.downcase(name)}_#{interval}_" <> Ecto.UUID.generate()
        )
    end
  end

  defp business_pro_plan do
    Repo.get_by(Plan, name: "BUSINESS_PRO", interval: "month")
  end
end
