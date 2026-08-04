defmodule Sanbase.ApiCallLimit.BundleQuotaTest do
  @moduledoc ~s"""
  The write half of a bundle's call quota: how the resolved numbers get onto the
  `api_call_limits` row, and that nobody else's row changes shape.

  A bundle's limits are the one thing about it that cannot be derived from its plan
  name, so they are resolved when the subscription syncs and stored. Everything
  asserted here is about that store staying truthful:

    * it is written when the entitlement is resolved, and again when it changes
    * it is cleared when the customer stops being on a bundle
    * it stays `nil` for every other plan, which is what makes this change
      invisible to existing customers
  """

  use Sanbase.DataCase, async: false

  @moduletag :api_call_counting

  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup context do
    ApiCallLimit.ETS.clear_all()
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

    bundle_plan =
      insert(:plan_pro,
        id: 9500,
        name: "BUNDLE",
        interval: "month",
        product_id: context.product_api.id,
        amount: 0,
        stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
      )

    publish_snapshot()

    # Not @santiment.net: those users are exempt from quota entirely, so a test on
    # one would pass without the numbers ever being read.
    user = insert(:user, email: "bundle_quota#{System.unique_integer([:positive])}@example.com")

    %{bundle_plan: bundle_plan, user: user}
  end

  describe "resolving an entitlement" do
    test "writes the resolved limits onto the row", %{user: user, bundle_plan: plan} do
      subscription = subscribe(user, plan, ["social", "market"])

      {:ok, _} = Resolver.sync(subscription.id)

      assert acl(user).resolved_api_call_limits == %{
               "month" => Resolver.base_calls_per_month(),
               "hour" => 30_000,
               "minute" => 600
             }
    end

    test "rewrites them when an add-on changes the allowance", %{user: user, bundle_plan: plan} do
      # Without this, buying a call add-on would grant nothing until the next plan
      # change - the metrics would arrive immediately and the calls never.
      subscription = subscribe(user, plan, ["social"])
      {:ok, _} = Resolver.sync(subscription.id)

      before = acl(user).resolved_api_call_limits["month"]

      sku = hd(Bundle.ApiCallAddon.skus())
      {:ok, per_addon} = Bundle.ApiCallAddon.calls_per_month(sku)

      {:ok, _} =
        Item.create(%{subscription_id: subscription.id, sku: sku, type: :api_calls, quantity: 3})

      {:ok, _} = Resolver.sync(subscription.id)

      assert acl(user).resolved_api_call_limits["month"] == before + 3 * per_addon
    end

    test "the quota path reads what was written", %{user: user, bundle_plan: plan} do
      subscription = subscribe(user, plan, ["social"])
      {:ok, _} = Resolver.sync(subscription.id)

      {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

      assert result.plan == "sanapi_bundle"
      assert result.has_limits == true
      assert result.api_calls_limits.month == Resolver.base_calls_per_month()
      assert result.api_calls_remaining.month == Resolver.base_calls_per_month()
    end

    test "a bundle row that was never synced refuses rather than inventing numbers", %{
      user: user,
      bundle_plan: plan
    } do
      # The subscription exists and the plan name says bundle, but nothing resolved
      # an entitlement. Reached by asking for the quota without ever syncing.
      subscribe(user, plan, ["social"])
      {:ok, _} = ApiCallLimit.update_user_plan(user)

      assert acl(user).api_calls_limit_plan == "sanapi_bundle"
      assert acl(user).resolved_api_call_limits == nil

      assert_raise Bundle.NotImplementedError, fn ->
        ApiCallLimit.usage_and_limits(:user, user)
      end
    end
  end

  describe "existing plans are unaffected" do
    test "a standard plan stores nothing and keeps the ladder's numbers", %{user: user} do
      insert(:subscription_pro, user_id: user.id, status: :active)

      {:ok, _} = ApiCallLimit.update_user_plan(user)

      assert acl(user).resolved_api_call_limits == nil

      {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)

      assert result.api_calls_limits == ApiCallLimit.plan_to_api_call_limits("sanapi_pro")
    end

    test "a user with no subscription stores nothing", %{user: user} do
      {:ok, _} = ApiCallLimit.update_user_plan(user)

      assert acl(user).api_calls_limit_plan == "sanapi_free"
      assert acl(user).resolved_api_call_limits == nil
    end

    test "moving off a bundle clears the stored limits", %{user: user, bundle_plan: plan} do
      # The case a stale value would break: the row would keep the bundle's
      # allowance while the customer is billed for something else.
      subscription = subscribe(user, plan, ["social"])
      {:ok, _} = Resolver.sync(subscription.id)

      assert acl(user).resolved_api_call_limits != nil

      # Off the bundle and onto a standard plan.
      Repo.delete!(subscription)
      insert(:subscription_pro, user_id: user.id, status: :active)

      {:ok, _} = ApiCallLimit.update_user_plan(user)

      assert acl(user).api_calls_limit_plan == "sanapi_pro"
      assert acl(user).resolved_api_call_limits == nil

      {:ok, result} = ApiCallLimit.usage_and_limits(:user, user)
      assert result.api_calls_limits == ApiCallLimit.plan_to_api_call_limits("sanapi_pro")
    end
  end

  # ── Helpers ─────────────────────────────────────────────────────────────

  defp acl(user), do: Repo.get_by!(ApiCallLimit, user_id: user.id)

  defp subscribe(user, plan, packages) do
    subscription =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: plan.id,
        status: :active,
        stripe_id: "sub_" <> Ecto.UUID.generate()
      )

    for slug <- packages do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: slug, type: :package})
    end

    subscription
  end

  defp publish_snapshot do
    for {package, index} <- Enum.with_index(Bundle.Package.all()) do
      {:ok, category} = MetricCategory.create(%{name: package.category, display_order: index})

      {:ok, _} =
        MetricCategoryMapping.create(%{
          module: "Sanbase.Metric.BundleQuotaTestAdapter",
          metric: Map.fetch!(@packaged_metrics, package.slug),
          category_id: category.id
        })
    end

    {:ok, snapshot} = PackageSnapshot.publish(notes: "test")
    snapshot
  end
end
