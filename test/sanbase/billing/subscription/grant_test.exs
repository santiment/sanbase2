defmodule Sanbase.Billing.Subscription.GrantTest do
  @moduledoc ~s"""
  Sales-applied add-ons: extra monthly API calls and full history on individual
  data packages. See §8 task **GR** of `docs/composable-api-plans-handover.md`.

  Two properties carry most of the weight here and each has its own block.

  **A grant can only add.** It may raise a call allowance or widen a history
  window and never the reverse, which is what makes applying one safe without
  reasoning about the plan underneath. That is enforced in code, so it is pinned
  in code.

  **No grant means nothing changed.** Every answer for a customer without one has
  to be byte-identical to what it was before grants existed, because that is
  every customer today. The access-matrix fixture proves it across the whole
  surface; these tests prove it at the two functions that learned about grants.
  """

  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Grant
  alias Sanbase.Billing.Subscription.Grants
  alias Sanbase.Repo

  @plan "INSTITUTIONAL"
  @acl_plan "sanapi_institutional"

  # Three years, the Institutional window every ungranted metric keeps.
  @institutional_history 3 * 365

  # Both are restricted metrics with a real history window, so the plan's three years
  # is observable and a grant widening it to "no limit" is too. A freely available
  # metric has no window at all and would prove nothing either way.
  @market_metric "mvrv_usd"
  @social_metric "social_volume_total"

  setup do
    snapshot = publish_snapshot()
    user = insert(:user)
    subscription = insert_institutional_subscription(user)

    %{user: user, subscription: subscription, snapshot: snapshot}
  end

  describe "the changeset" do
    test "refuses a grant that grants nothing" do
      # A form submitted empty would otherwise store a row that reads as an add-on
      # while changing nothing, which is worse than an error.
      changeset = Grant.changeset(%Grant{}, base_attrs())

      refute changeset.valid?
      assert errors_on(changeset)[:extra_api_calls_per_month]
    end

    test "refuses an unknown package" do
      changeset =
        Grant.changeset(%Grant{}, base_attrs(full_history_packages: ["market", "nonsense"]))

      refute changeset.valid?
      assert errors_on(changeset)[:full_history_packages]
    end

    test "refuses a negative call grant" do
      changeset = Grant.changeset(%Grant{}, base_attrs(extra_api_calls_per_month: -1))

      refute changeset.valid?
    end

    test "requires a note" do
      # The only record that money changed hands is an invoice raised elsewhere, so
      # the reference has to live with the grant.
      changeset =
        Grant.changeset(%Grant{}, %{extra_api_calls_per_month: 1000, granted_at: now()})

      refute changeset.valid?
      assert errors_on(changeset)[:note]
    end

    test "accepts calls alone, packages alone, and both" do
      for attrs <- [
            base_attrs(extra_api_calls_per_month: 1000),
            base_attrs(full_history_packages: ["market"]),
            base_attrs(extra_api_calls_per_month: 1000, full_history_packages: ["market"])
          ] do
        assert Grant.changeset(%Grant{}, attrs).valid?
      end
    end
  end

  describe "writing a grant" do
    test "expands the chosen packages into metrics and records who granted it", context do
      %{subscription: subscription, user: user, snapshot: snapshot} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{full_history_packages: ["market"], note: "INV-1"},
          user
        )

      grant = Subscription.grant(subscription)

      assert grant.full_history_packages == ["market"]
      assert @market_metric in grant.full_history_metrics
      refute @social_metric in grant.full_history_metrics
      assert grant.package_snapshot_version == snapshot.version
      assert grant.granted_by_id == user.id
      assert grant.granted_at
    end

    test "\"all\" is stored as itself rather than expanded", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{full_history_packages: [Grant.all_packages()], note: "INV-2"},
          user
        )

      grant = Subscription.grant(subscription)

      # Nothing is frozen, so a package added later is covered without anyone
      # having to remember to re-expand.
      assert grant.full_history_metrics == []
      assert Grant.full_history?(grant, "a_metric_that_did_not_exist_yet")
    end

    test "replaces rather than merges", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{full_history_packages: ["market"], note: "INV-1"}, user)

      {:ok, subscription} =
        Grants.grant(subscription, %{full_history_packages: ["social"], note: "INV-2"}, user)

      grant = Subscription.grant(subscription)

      # The dropped package must lose the metrics it expanded, or removing a
      # package from a grant would leave what it gave behind.
      assert grant.full_history_packages == ["social"]
      refute @market_metric in grant.full_history_metrics
      assert @social_metric in grant.full_history_metrics
    end

    test "revoking puts the customer back on exactly the plan", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{extra_api_calls_per_month: 200_000, note: "INV-1"}, user)

      {:ok, subscription} = Grants.revoke(subscription)

      assert Subscription.grant(subscription) == nil
      assert acl_month(user) == plan_month()
    end
  end

  describe "history: what the grant widens and what it leaves alone" do
    test "no grant answers exactly as the plan does" do
      assert history_for(@market_metric, nil) == @institutional_history
      assert history_for(@social_metric, nil) == @institutional_history
    end

    test "a granted package gets full history and nothing else moves", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{full_history_packages: ["market"], note: "INV-1"}, user)

      grant = Subscription.grant(subscription)

      # `nil` is what "no limit" already means everywhere else here.
      assert history_for(@market_metric, grant) == nil
      assert history_for(@social_metric, grant) == @institutional_history
    end

    test "granting every package widens everything", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{full_history_packages: [Grant.all_packages()], note: "INV-1"},
          user
        )

      grant = Subscription.grant(subscription)

      assert history_for(@market_metric, grant) == nil
      assert history_for(@social_metric, grant) == nil
    end

    test "a calls-only grant does not touch history", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{extra_api_calls_per_month: 200_000, note: "INV-1"}, user)

      grant = Subscription.grant(subscription)

      assert history_for(@market_metric, grant) == @institutional_history
    end

    test "queries and signals are unaffected", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{full_history_packages: [Grant.all_packages()], note: "INV-1"},
          user
        )

      grant = Subscription.grant(subscription)

      # A package sells metrics. There is no history window on a query or signal
      # that a package could have bought, so "all" must not reach them.
      for query_or_argument <- [{:query, :miners_balance}, {:signal, "dai_mint"}] do
        assert AccessChecker.historical_data_in_days(
                 query_or_argument,
                 "SANAPI",
                 "SANAPI",
                 @plan,
                 nil,
                 grant
               ) ==
                 AccessChecker.historical_data_in_days(
                   query_or_argument,
                   "SANAPI",
                   "SANAPI",
                   @plan
                 )
      end
    end
  end

  describe "API calls" do
    test "a grant is added to the plan's allowance", context do
      %{subscription: subscription, user: user} = context

      {:ok, _} =
        Grants.grant(subscription, %{extra_api_calls_per_month: 200_000, note: "INV-1"}, user)

      assert acl_month(user) == plan_month() + 200_000
    end

    test "the burst limits are not widened", context do
      %{subscription: subscription, user: user} = context

      {:ok, _} =
        Grants.grant(subscription, %{extra_api_calls_per_month: 200_000, note: "INV-1"}, user)

      limits = user |> acl() |> ApiCallLimit.acl_to_api_call_limits()
      from_plan = ApiCallLimit.plan_to_api_call_limits(@acl_plan)

      # Hour and minute protect the infrastructure; they are not a thing being sold.
      assert limits.hour == from_plan.hour
      assert limits.minute == from_plan.minute
    end

    test "a history-only grant leaves the allowance alone", context do
      %{subscription: subscription, user: user} = context

      {:ok, _} =
        Grants.grant(subscription, %{full_history_packages: ["market"], note: "INV-1"}, user)

      assert acl_month(user) == plan_month()
    end

    test "a stored value below the plan's is a leftover and is ignored" do
      # A customer who moved off a bundle, or a bad backfill. A grant can only add,
      # so anything at or under the plan's number cannot be one.
      acl = %ApiCallLimit{
        api_calls_limit_plan: "sanapi_pro",
        resolved_api_call_limits: %{"month" => 1, "hour" => 1, "minute" => 1}
      }

      assert ApiCallLimit.acl_to_api_call_limits(acl) ==
               ApiCallLimit.plan_to_api_call_limits("sanapi_pro")
    end
  end

  describe "re-expanding" do
    test "picks up metrics added to a granted package since the grant", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{full_history_packages: ["market"], note: "INV-1"}, user)

      refute "grant_test_late_market_metric" in Subscription.grant(subscription).full_history_metrics

      categorize("grant_test_late_market_metric", category_for("Market"))
      {:ok, _} = PackageSnapshot.publish()

      {:ok, subscription} = Grants.re_expand(subscription)
      grant = Subscription.grant(subscription)

      assert "grant_test_late_market_metric" in grant.full_history_metrics
      # Everything else about the grant survives - this refreshes, it does not rewrite.
      assert grant.note == "INV-1"
      assert grant.granted_by_id == user.id
    end

    test "a grant is frozen until someone re-expands it", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(subscription, %{full_history_packages: ["market"], note: "INV-1"}, user)

      categorize("grant_test_another_late_metric", category_for("Market"))
      {:ok, _} = PackageSnapshot.publish()

      # Deliberate: a customer keeps what they bought until someone decides otherwise.
      refute Grant.full_history?(
               Subscription.grant(subscription),
               "grant_test_another_late_metric"
             )
    end

    test "says so when there is nothing to re-expand", context do
      assert {:error, message} = Grants.re_expand(context.subscription)
      assert message =~ "no grant"
    end
  end

  describe "describe/1" do
    test "reports the resolved result and whether the snapshot has moved on", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{extra_api_calls_per_month: 200_000, full_history_packages: ["market"], note: "INV-1"},
          user
        )

      described = Grants.describe(subscription)

      assert described.extra_api_calls_per_month == 200_000
      assert described.full_history_packages == ["market"]
      assert described.full_history_metric_count > 0
      assert described.snapshot_is_current?

      categorize("grant_test_yet_another_metric", category_for("Market"))
      {:ok, _} = PackageSnapshot.publish()

      refute Grants.describe(Repo.reload(subscription)).snapshot_is_current?
    end

    test "is nil without a grant", context do
      assert Grants.describe(context.subscription) == nil
    end

    test "an \"all packages\" grant never reports as stale", context do
      %{subscription: subscription, user: user} = context

      {:ok, subscription} =
        Grants.grant(
          subscription,
          %{full_history_packages: [Grant.all_packages()], note: "INV-1"},
          user
        )

      categorize("grant_test_metric_after_all", category_for("Market"))
      {:ok, _} = PackageSnapshot.publish()

      # Nothing was frozen, so a newer snapshot leaves nothing behind and there is
      # nothing to re-expand. Warning here would make the warning mean less where it
      # does matter.
      assert Grants.describe(Repo.reload(subscription)).snapshot_is_current?
      assert Grant.full_history?(Subscription.grant(subscription), "grant_test_metric_after_all")
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp base_attrs(extra \\ []) do
    Map.merge(%{note: "INV-0", granted_at: now()}, Map.new(extra))
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp history_for(metric, grant) do
    AccessChecker.historical_data_in_days(
      {:metric, metric},
      "SANAPI",
      "SANAPI",
      @plan,
      nil,
      grant
    )
  end

  defp plan_month, do: ApiCallLimit.plan_to_api_call_limits(@acl_plan).month

  defp acl_month(user),
    do: user |> acl() |> ApiCallLimit.acl_to_api_call_limits() |> Map.get(:month)

  defp acl(user), do: Repo.get_by!(ApiCallLimit, user_id: user.id)

  defp insert_institutional_subscription(user) do
    product_api_id = Sanbase.Billing.Product.product_api()

    # The migration seeds this row against products.id = 1, which does not exist when
    # the test database is migrated - so it is created here, with an explicit id out of
    # the factories' way.
    plan =
      Repo.get_by(Plan, name: @plan, interval: "year", product_id: product_api_id) ||
        insert(:plan_pro,
          id: 9801,
          name: @plan,
          product_id: product_api_id,
          interval: "year",
          amount: 958_800,
          is_private: true,
          stripe_id: "plan_institutional_year_" <> Ecto.UUID.generate()
        )

    insert(:subscription_pro,
      user_id: user.id,
      plan_id: plan.id,
      status: :active,
      stripe_id: "sub_grant_" <> Ecto.UUID.generate()
    )
    |> Repo.preload([:plan, :user])
  end

  # Two categorized metrics in two different packages, so a grant on one is
  # observably not a grant on the other.
  defp publish_snapshot do
    Sanbase.Billing.Plan.Bundle.Package.all()
    |> Enum.with_index()
    |> Enum.each(fn {package, index} ->
      {:ok, _} =
        Sanbase.Metric.Category.MetricCategory.create(%{
          name: package.category,
          display_order: index
        })
    end)

    categorize_existing(@market_metric, category_for("Market"))
    categorize_existing(@social_metric, category_for("Social"))

    {:ok, snapshot} = PackageSnapshot.publish()
    snapshot
  end

  defp category_for(name), do: Repo.get_by!(Sanbase.Metric.Category.MetricCategory, name: name)

  defp categorize(metric, category) do
    registry = Sanbase.MetricRegistryHelpers.create_registry_metric(metric)

    map_to_category(registry, category)
  end

  # The seeded registry already holds the real metrics, so these are looked up rather
  # than created - creating one would collide with the seed.
  defp categorize_existing(metric, category) do
    {:ok, registry} = Sanbase.Metric.Registry.by_name(metric)

    map_to_category(registry, category)
  end

  defp map_to_category(registry, category) do
    {:ok, _} =
      Sanbase.Metric.Category.MetricCategoryMapping.create(%{
        metric_registry_id: registry.id,
        category_id: category.id
      })
  end
end
