defmodule Sanbase.Billing.Plan.EnterpriseTest do
  @moduledoc ~s"""
  What the `ENTERPRISE` plan grants, and who is allowed to buy it.

  Enterprise is the right column of the new SanAPI offering (§1.1) and it is built
  the same way Institutional is: a fixed plan on the standard path, with access and
  quota declared in code rather than assembled from purchased items. So the work is
  one clause per plan-dependent `case`, and the failure mode is a missing clause -
  either a `CaseClauseError` on the first real request, or a catch-all quietly
  answering as if the customer were on FREE.

  This file pins the values that differ from Institutional's, because those two
  differences *are* the tier:

    * unlimited history, where Institutional stops at three years.
    * 300,000 calls a month, six times Institutional's, with BUSINESS_MAX's bursts
      rather than PRO's so the monthly figure is actually reachable.

  It also pins the things that are deliberately *not* different, since inventing a
  bigger number for every dimension would produce a set of values nobody decided.

  ## Enterprise is not `CUSTOM_*`

  Those two words were used interchangeably for years, because every Enterprise deal
  used to be a hand-built `CUSTOM_<NAME>` plan at a negotiated price. This tier is
  the opposite: one published price for a declared set of access. Several tests here
  exist only to hold that line - the plan must not be classified `:custom`, and it
  must not inherit the unlimited-quota exemption that bespoke contracts get.

  See `docs/composable-api-plans-handover.md` §8 task EP.
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

  @plan "ENTERPRISE"
  @acl_plan "sanapi_enterprise"

  # A metric and a query that a FREE user cannot have in full, so "full SanAPI"
  # is actually being asserted rather than a free-for-all answer.
  @restricted_metric {:metric, "mvrv_usd"}
  @pro_only_query {:query, :miners_balance}

  describe "plan classification" do
    test "is a standard plan, not a bundle and not a custom one" do
      assert Plan.type(@plan) == :standard
      assert Plan.type_of_api_call_limit_plan(@acl_plan) == :standard
    end

    test "reaches the access layer under its own name" do
      # plan_name/1 is the first function an authenticated request hits. Without a
      # clause it raises CaseClauseError before any other code runs - which is
      # exactly what ENTERPRISE_BASIC and ENTERPRISE_PLUS did for four years while
      # being listed on the pricing page.
      assert Plan.plan_name(%Plan{name: @plan}) == @plan
    end
  end

  describe "SanAPI access" do
    test "grants the metrics and queries a paid API plan grants" do
      assert AccessChecker.plan_has_access?(@restricted_metric, "SANAPI", @plan)
      assert AccessChecker.plan_has_access?(@pro_only_query, "SANAPI", @plan)
    end

    test "history is unlimited, where Institutional stops at three years" do
      # The whole difference between the two tiers on this dimension. `nil` means no
      # limit, the same answer BUSINESS_MAX gives.
      assert data_windows(@restricted_metric, "SANAPI") == %{history: nil, cut_off: 0}

      assert AccessChecker.historical_data_in_days(
               @restricted_metric,
               "SANAPI",
               "SANAPI",
               "INSTITUTIONAL"
             ) == 3 * 365
    end

    test "the window does not depend on which item is asked about" do
      assert data_windows(@pro_only_query, "SANAPI") == %{history: nil, cut_off: 0}
    end

    test "realtime data is included" do
      assert data_windows(@restricted_metric, "SANAPI").cut_off == 0
    end

    test "the metric catalog can be browsed by plan name alone" do
      # `getAvailableMetrics(plan: ENTERPRISE)` reaches here.
      metrics = AccessChecker.get_available_metrics_for_plan(@plan, "SANAPI", :all)

      assert {:metric, metric} = @restricted_metric
      assert metric in metrics
    end
  end

  describe "Sanbase access" do
    test "answers as MAX, the same as Institutional" do
      # Enterprise is Institutional plus API, and there is nothing above MAX for
      # Sanbase to give.
      assert SanbaseAccessChecker.alerts_limit(@plan) == SanbaseAccessChecker.alerts_limit("MAX")

      assert SanbaseAccessChecker.can_access_paywalled_insights?(%Subscription{
               plan: %Plan{name: @plan}
             })
    end
  end

  describe "call quota" do
    test "300,000 calls a month, the figure on the pricing page" do
      assert ApiCallLimit.plan_to_api_call_limits(@acl_plan) == %{
               month: 300_000,
               hour: 60_000,
               minute: 1200
             }
    end

    test "six times Institutional's monthly allowance" do
      assert ApiCallLimit.plan_to_api_call_limits(@acl_plan).month ==
               6 * ApiCallLimit.plan_to_api_call_limits("sanapi_institutional").month
    end

    test "bursts are BUSINESS_MAX's, so the month is reachable" do
      # At Institutional's 30,000 an hour a customer would need ten full hours of
      # sustained traffic to spend a month's allowance, which turns a volume tier
      # into a throttling complaint.
      assert ApiCallLimit.plan_to_api_call_limits(@acl_plan)
             |> Map.take([:hour, :minute]) ==
               ApiCallLimit.plan_to_api_call_limits("sanapi_business_max")
               |> Map.take([:hour, :minute])
    end

    test "has limits at all" do
      # The load-bearing test of this file. `"sanapi_enterprise"` used to sit in
      # `@plans_without_limits`, from when Enterprise meant a bespoke contract with
      # no ceiling. Left there, this tier would have published a 300,000 cap and
      # enforced nothing.
      assert ApiCallLimit.plan_has_limits?(@acl_plan)
    end

    test "bespoke custom plans keep their exemption" do
      # The other half: removing the Enterprise key must not have taken the CUSTOM
      # one with it.
      refute ApiCallLimit.plan_has_limits?("sanapi_custom")
    end

    test "response size is capped at the largest figure in the table" do
      assert ApiCallLimit.plan_to_response_size_limits(@acl_plan) == %{month: 100_000}

      assert ApiCallLimit.plan_to_response_size_limits(@acl_plan) ==
               ApiCallLimit.plan_to_response_size_limits("sanapi_business_max")
    end
  end

  describe "Queries and complexity" do
    test "gets the widest table access and BUSINESS_MAX's credits" do
      # Neither of these is a dimension Enterprise sells, so they answer as the top
      # standard tier rather than as numbers invented to look bigger.
      for site <- [:repo, :credits] do
        assert authorization(site, @plan) == authorization(site, "BUSINESS_MAX"),
               "#{site} should answer as BUSINESS_MAX"
      end
    end

    test "query executions are CUSTOM's, the highest in the table" do
      # Above BUSINESS_MAX here, and only here: SQL throughput is the one query-side
      # dimension where the top standard tier is not already the ceiling.
      assert authorization(:executions, @plan) == authorization(:executions, "CUSTOM")

      assert authorization(:executions, @plan) != authorization(:executions, "INSTITUTIONAL")
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
    test "an Enterprise subscriber is MAX tier" do
      # classify/2 has a catch-all returning :free, so a missing clause here would
      # not raise - it would silently sell MCP and then serve 15 calls a minute.
      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: enterprise_plan().id,
        status: :active,
        stripe_id: "sub_ent_" <> Ecto.UUID.generate()
      )

      assert Sanbase.MCP.Restrictions.tier_for_user(user) == :max
    end
  end

  describe "who may buy it" do
    setup do
      insert(:role_san_team)
      enterprise_plan()
      bundle_plan("month")

      %{user: insert(:user, stripe_customer_id: "cus_ent_" <> Ecto.UUID.generate())}
    end

    test "not for sale while the new offering is deactivated", %{user: user} do
      assert {:error, "The Enterprise plan is not available for purchase yet"} =
               Lifecycle.ensure_can_subscribe_enterprise(user)
    end

    test "a team member can buy it while it is deactivated", %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

      assert :ok = Lifecycle.ensure_can_subscribe_enterprise(user)
    end

    test "for sale once the offering is activated", %{user: user} do
      activate_offering()

      assert :ok = Lifecycle.ensure_can_subscribe_enterprise(user)
    end

    test "refused to a customer who already has a bundle", %{user: user} do
      activate_offering()

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: bundle_plan("month").id,
        status: :active,
        stripe_id: "sub_bundle_" <> Ecto.UUID.generate()
      )

      assert {:error, "You already have an active SanAPI subscription on the new offering"} =
               Lifecycle.ensure_can_subscribe_enterprise(user)
    end

    test "refused to a customer who already has Institutional", %{user: user} do
      # Enterprise is the upgrade path from Institutional, and this is why that path
      # has to go through `updateSubscription` rather than a second `subscribe`.
      activate_offering()

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: institutional_plan("month").id,
        status: :active,
        stripe_id: "sub_inst_" <> Ecto.UUID.generate()
      )

      assert {:error, "You already have an active SanAPI subscription on the new offering"} =
               Lifecycle.ensure_can_subscribe_enterprise(user)
    end

    test "allowed while a replaceable legacy subscription is still live", %{user: user} do
      # The legacy subscription is not canceled here. It is canceled with proration
      # by cancel_stale_replaced_subscriptions/0 once the new one is actually live.
      activate_offering()

      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: business_pro_plan().id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      assert :ok = Lifecycle.ensure_can_subscribe_enterprise(user)
      assert Repo.reload!(legacy).status == :active
    end

    test "an active Enterprise subscription makes a legacy one stale" do
      # The replacement job has to recognise Enterprise as new-offering, or a
      # customer who upgrades from BUSINESS_PRO keeps paying for both forever.
      activate_offering()
      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: enterprise_plan().id,
        status: :active,
        stripe_id: "sub_ent_" <> Ecto.UUID.generate()
      )

      legacy_stripe_id = "sub_legacy_" <> Ecto.UUID.generate()

      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: business_pro_plan().id,
          status: :active,
          stripe_id: legacy_stripe_id
        )

      with_mocks([
        {StripeApi, [:passthrough],
         [
           cancel_subscription_with_proration: fn stripe_id ->
             Sanbase.StripeApiTestResponse.cancel_subscription_with_proration_resp(
               stripe_id: stripe_id
             )
           end
         ]}
      ]) do
        assert %{canceled: 1, failed: 0} = Lifecycle.cancel_stale_replaced_subscriptions()

        # With proration, so the customer is credited for the unused part of the
        # plan Enterprise replaced.
        assert_called(StripeApi.cancel_subscription_with_proration(legacy_stripe_id))
      end

      assert Repo.reload!(legacy).status == :canceled
    end

    test "the sale switch is checked on its own, without the one-subscription rule" do
      # What `updateSubscription` needs: that path replaces the subscription it is
      # called on, so a customer who already has a live SanAPI subscription must not
      # be refused for having one - but the plan still has to be for sale.
      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: business_pro_plan().id,
        status: :active,
        stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
      )

      assert {:error, "The Enterprise plan is not available for purchase yet"} =
               Lifecycle.ensure_enterprise_for_sale(user)

      activate_offering()

      assert :ok = Lifecycle.ensure_enterprise_for_sale(user)
    end

    test "subscribe refuses before charging anything", %{user: user} do
      # The gate is only worth having if it runs before Stripe does. If it moved
      # below the charge, the customer would be billed $19,999 and then told no.
      with_mocks([
        {StripeApi, [:passthrough],
         [
           create_customer_with_card: fn _, _ ->
             {:ok, %Stripe.Customer{id: "cus_never_created"}}
           end,
           update_customer_card: fn _, _ ->
             {:ok, %Stripe.Customer{id: "cus_never_updated"}}
           end,
           create_subscription: fn _ -> {:ok, %Stripe.Subscription{id: "sub_never_created"}} end
         ]}
      ]) do
        assert {:error, %Subscription.Error{message: message}} =
                 Subscription.subscribe(user, enterprise_plan(), "card_token")

        assert message == "The Enterprise plan is not available for purchase yet"

        assert_not_called(StripeApi.create_customer_with_card(:_, :_))
        assert_not_called(StripeApi.update_customer_card(:_, :_))
        assert_not_called(StripeApi.create_subscription(:_))
      end
    end

    test "a retired legacy plan cannot be bought by plan id", %{user: user} do
      # Delisting is not a purchase gate: `is_private` is enforced nowhere (§15 Q14)
      # and `subscribe` takes an id, not a name. Without a refusal the buyer would be
      # charged $1,500 and then hit `CaseClauseError` in `plan_name/1` on every
      # authenticated request afterwards - the original bug, still reachable by
      # anyone who knew the id was 105.
      retired = retired_legacy_plan()

      with_mocks(stripe_mocks()) do
        assert {:error, %Subscription.Error{message: message}} =
                 Subscription.subscribe(user, retired, "card_token")

        assert message == "This plan is no longer available for purchase"
        assert_not_called(StripeApi.create_subscription(:_))
      end
    end

    test "no trial, however new the plan is", %{user: user} do
      # A free fortnight of unlimited history is the whole product. Trials for this
      # tier are task TR's to decide, not something it inherits by being new. The
      # assertion is on the params handed to Stripe, because `subscription_defaults/2`
      # is private and this is where its output actually matters.
      activate_offering()

      with_mocks(stripe_mocks()) do
        assert {:ok, _} = Subscription.subscribe(user, enterprise_plan(), "card_token")

        assert_receive {:stripe_subscription_params, params}
        refute Map.has_key?(params, :trial_end)
      end
    end
  end

  describe "the plan rows" do
    test "are kept out of the pricing page listing" do
      # Same reason as Institutional: the legacy pricing grid renders a column per
      # row and knows nothing about the three-column offering.
      enterprise_plan()

      assert {:ok, products} = Plan.product_with_plans()

      refute @plan in Enum.flat_map(products, fn product ->
               Enum.map(product.plans, & &1.name)
             end)
    end

    test "a retired legacy row is out of the listing too" do
      # `ENTERPRISE_BASIC` and `ENTERPRISE_PLUS` were on the pricing page for four
      # years with no access-checker clause behind them, so buying one raised
      # `CaseClauseError`. The migration renames them, and renaming alone is not
      # enough to delist them - `product_with_plans/0` applies `is_deprecated` only
      # to the Business names, so a `RETIRED_*` row passes every other predicate and
      # would still be listed, now under a name that reads like debug output. Hence
      # the explicit `RETIRED_%` exclusion, which this asserts.
      retired = retired_legacy_plan()

      assert {:ok, products} = Plan.product_with_plans()

      listed =
        Enum.flat_map(products, fn product -> Enum.map(product.plans, & &1.name) end)

      refute retired.name in listed
      refute Enum.any?(listed, &String.contains?(&1, "ENTERPRISE"))
    end

    test "are toggled by the same switch as the bundle rows" do
      # One switch for the whole offering. Two would allow a state where the pricing
      # page shows a column nobody can buy.
      enterprise = enterprise_plan()
      bundle_plan("month")

      assert {:ok, ids} = Sanbase.Billing.Plan.SaleControls.activate_bundle_plans()
      assert enterprise.id in ids
      refute Repo.reload!(enterprise).is_private
    end

    test "an Enterprise row alone is enough to report the offering active" do
      enterprise_plan()

      refute Sanbase.Billing.Plan.SaleControls.bundle_plans_active?()

      Repo.update_all(
        Ecto.Query.from(p in Plan, where: p.name == ^@plan),
        set: [is_private: false]
      )

      assert Sanbase.Billing.Plan.SaleControls.bundle_plans_active?()
    end

    test "a retired legacy row does not report the offering active" do
      retired_legacy_plan(is_private: false)

      refute Sanbase.Billing.Plan.SaleControls.bundle_plans_active?()
    end

    test "an un-renamed legacy row does not report the offering active either" do
      # The state production is in before `20260810121347` runs, and the state it
      # returns to if that migration is rolled back: `ENTERPRISE_BASIC` still named
      # that, and public, because the 2022 migration never set `is_private` and the
      # column defaults to false.
      #
      # Matching the new offering as `ENTERPRISE%` made this row alone answer the
      # sale switch, putting bundles and Institutional on public sale as well - with
      # the admin Deactivate button greyed out, because the panel reads the same
      # answer. This is why the switch matches `"ENTERPRISE"` exactly.
      legacy = legacy_enterprise_plan()

      refute legacy.is_private
      refute Sanbase.Billing.Plan.SaleControls.bundle_plans_active?()
    end

    test "an un-renamed legacy row is not touched by the sale switch" do
      # The other half of the same rule. Were it matched, `activate_bundle_plans/0`
      # would un-hide a row nobody can buy, and `deactivate_bundle_plans/0` would
      # report it in the count an operator uses to judge the blast radius.
      legacy = legacy_enterprise_plan()
      enterprise = enterprise_plan()

      assert {:ok, activated} = Sanbase.Billing.Plan.SaleControls.activate_bundle_plans()
      assert enterprise.id in activated
      refute legacy.id in activated

      assert {:ok, deactivated} = Sanbase.Billing.Plan.SaleControls.deactivate_bundle_plans()
      refute legacy.id in deactivated

      # The row count the admin panel shows next to the switch comes from here.
      refute legacy.id in Sanbase.Billing.Plan.SaleControls.status().bundle_plan_ids
    end

    test "an un-renamed legacy row is still kept out of the pricing page listing" do
      # `product_with_plans/0` keeps the `ENTERPRISE%` prefix on purpose: there,
      # matching the legacy rows is the point. It delists them on deploy rather than
      # on migrate, which is what stops `subscribe(planId: 105)` being discoverable.
      legacy = legacy_enterprise_plan()

      assert {:ok, products} = Plan.product_with_plans()

      refute legacy.name in Enum.flat_map(products, fn product ->
               Enum.map(product.plans, & &1.name)
             end)
    end

    test "an un-renamed legacy row does not get another subscription canceled" do
      # The worst of the three. Treating an `ENTERPRISE_BASIC` holder as a
      # new-offering customer would have had the scheduled replacement job cancel
      # their genuine, paid SanAPI subscription - with proration, in Stripe,
      # unprompted.
      user = insert(:user)

      insert(:subscription_pro,
        user_id: user.id,
        plan_id: legacy_enterprise_plan().id,
        status: :active,
        stripe_id: "sub_legacy_ent_" <> Ecto.UUID.generate()
      )

      other =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: business_pro_plan().id,
          status: :active,
          stripe_id: "sub_other_" <> Ecto.UUID.generate()
        )

      with_mocks([
        {StripeApi, [:passthrough],
         [
           cancel_subscription_with_proration: fn stripe_id ->
             Sanbase.StripeApiTestResponse.cancel_subscription_with_proration_resp(
               stripe_id: stripe_id
             )
           end
         ]}
      ]) do
        assert %{canceled: 0, failed: 0} = Lifecycle.cancel_stale_replaced_subscriptions()
        assert_not_called(StripeApi.cancel_subscription_with_proration(:_))
      end

      assert Repo.reload!(other).status == :active
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

  # A full happy-path mock set, with `create_subscription/1` forwarding the params it
  # was given back to the test process. `update_customer_card/2` is the call that
  # actually fires: the user already has a `stripe_customer_id`, so a card token
  # updates the customer rather than creating one.
  defp stripe_mocks do
    test_pid = self()

    [
      {StripeApi, [:passthrough],
       [
         create_product: fn _ -> Sanbase.StripeApiTestResponse.create_product_resp() end,
         create_plan: fn _ -> Sanbase.StripeApiTestResponse.create_plan_resp() end,
         create_customer_with_card: fn _, _ ->
           Sanbase.StripeApiTestResponse.create_or_update_customer_resp()
         end,
         update_customer_card: fn _, _ ->
           Sanbase.StripeApiTestResponse.create_or_update_customer_resp()
         end,
         create_coupon: fn _ -> Sanbase.StripeApiTestResponse.create_coupon_resp() end,
         retrieve_coupon: fn coupon -> {:ok, %Stripe.Coupon{id: coupon, percent_off: 20}} end,
         create_subscription: fn params ->
           send(test_pid, {:stripe_subscription_params, params})
           Sanbase.StripeApiTestResponse.create_subscription_resp()
         end
       ]},
      {Sanbase.Messaging.Discord, [:passthrough], [send_notification: fn _, _, _ -> :ok end]},
      {Sanbase.TemplateMailer, [:passthrough],
       send: fn _, _, _ -> {:ok, %{"status" => "sent"}} end}
    ]
  end

  defp activate_offering do
    {:ok, _} = Sanbase.Billing.Plan.SaleControls.activate_bundle_plans()
    :ok
  end

  defp enterprise_plan, do: new_offering_plan(@plan, "year", 9801)
  defp institutional_plan(interval), do: new_offering_plan("INSTITUTIONAL", interval, 9811)
  defp bundle_plan(interval), do: new_offering_plan("BUNDLE", interval, 9821)

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
          amount: amount_for(name),
          is_private: true,
          is_deprecated: false,
          stripe_id: "plan_#{String.downcase(name)}_#{interval}_" <> Ecto.UUID.generate()
        )
    end
  end

  # What `20260810121347_retire_legacy_enterprise_plans.exs` finds. The 2022
  # migration inserted 105 and 106 without `is_private`, and the column defaults to
  # false, so on production these rows are public - which is what made prefix
  # matching on `ENTERPRISE%` a live problem rather than a hypothetical one.
  defp legacy_enterprise_plan do
    name = "ENTERPRISE_BASIC"
    product_api_id = Sanbase.Billing.Product.product_api()

    case Repo.get_by(Plan, name: name, product_id: product_api_id) do
      %Plan{} = plan ->
        plan

      nil ->
        Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9915")

        insert(:plan_pro,
          id: 9815,
          name: name,
          product_id: product_api_id,
          interval: "month",
          amount: 150_000,
          is_private: false,
          is_deprecated: false,
          stripe_id: "plan_legacy_enterprise_" <> Ecto.UUID.generate()
        )
    end
  end

  # What `20260810121347_retire_legacy_enterprise_plans.exs` leaves behind. Data
  # migrations never run in test - the test database is loaded from `structure.sql` -
  # so the post-migration shape has to be written here.
  defp retired_legacy_plan(opts \\ []) do
    name = "RETIRED_ENTERPRISE_BASIC"
    product_api_id = Sanbase.Billing.Product.product_api()

    case Repo.get_by(Plan, name: name, product_id: product_api_id) do
      %Plan{} = plan ->
        plan

      nil ->
        Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9905")

        insert(:plan_pro,
          id: 9805,
          name: name,
          product_id: product_api_id,
          interval: "month",
          amount: 150_000,
          is_private: Keyword.get(opts, :is_private, true),
          is_deprecated: true,
          stripe_id: "plan_retired_enterprise_" <> Ecto.UUID.generate()
        )
    end
  end

  defp amount_for(@plan), do: 1_999_900
  defp amount_for("INSTITUTIONAL"), do: 79_900
  defp amount_for(_), do: 0

  defp business_pro_plan do
    Repo.get_by(Plan, name: "BUSINESS_PRO", interval: "month")
  end
end
