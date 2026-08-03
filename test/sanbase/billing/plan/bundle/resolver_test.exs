defmodule Sanbase.Billing.Plan.Bundle.ResolverTest do
  @moduledoc ~s"""
  From "this customer bought Market and Social" to an entitlement that answers
  access and quota questions, and back out through the access checker.

  The pure `resolve/2` cases carry most of the weight - no database setup, so the
  rules themselves are readable. The `sync/1` cases then prove the same answer
  survives the round trip through the subscription row, and that recomputing is
  harmless.
  """

  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Billing.Plan.AccessChecker
  alias Sanbase.Billing.Plan.Bundle
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Resolver
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo

  @bundle_plan "BUNDLE"

  # Stands in for a published snapshot without touching the categorization
  # tables - resolve/2 only reads the contents.
  @snapshot %PackageSnapshot{
    version: 7,
    contents: %{
      "market" => ["price_usd", "volume_usd"],
      "development" => ["dev_activity"],
      "social" => ["social_volume_total", "sentiment_positive"],
      "onchain_core" => ["mvrv_usd"],
      "onchain_labels" => ["whale_transaction_count"]
    }
  }

  defp item(sku, type, quantity \\ 1), do: %{sku: sku, type: type, quantity: quantity}

  describe "resolve/2 - metrics" do
    test "grants the union of the purchased packages" do
      {:ok, attrs} =
        Resolver.resolve([item("market", :package), item("social", :package)], @snapshot)

      assert attrs.metric_access["accessible"] == [
               "price_usd",
               "sentiment_positive",
               "social_volume_total",
               "volume_usd"
             ]

      assert attrs.packages == ["market", "social"]
    end

    test "grants nothing from a package that was not bought" do
      {:ok, attrs} = Resolver.resolve([item("market", :package)], @snapshot)

      refute "dev_activity" in attrs.metric_access["accessible"]
      refute "mvrv_usd" in attrs.metric_access["accessible"]
    end

    test "records the snapshot version it resolved against" do
      # Without this, there is no way to tell which definition of "Market" a
      # customer is holding.
      {:ok, attrs} = Resolver.resolve([item("market", :package)], @snapshot)

      assert attrs.package_snapshot_version == 7
    end

    test "is stable for the same purchase in a different order" do
      # The stored value is compared to decide whether anything changed, so the
      # same purchase has to produce the same bytes.
      {:ok, one} =
        Resolver.resolve([item("social", :package), item("market", :package)], @snapshot)

      {:ok, two} =
        Resolver.resolve([item("market", :package), item("social", :package)], @snapshot)

      assert one == two
    end
  end

  describe "resolve/2 - queries and signals" do
    test "are all granted, matching what a free user can reach today" do
      # §6.4 - restricted means window-limited, not paywalled, so a package must
      # not narrow this. The allow-list denies by default, so it has to be said.
      {:ok, attrs} = Resolver.resolve([item("market", :package)], @snapshot)

      assert attrs.query_access == %{"accessible" => "all"}
      assert attrs.signal_access == %{"accessible" => "all"}
    end
  end

  describe "resolve/2 - API call limits" do
    test "one package gets the flat monthly allowance" do
      {:ok, attrs} = Resolver.resolve([item("market", :package)], @snapshot)

      assert attrs.api_call_limits["month"] == 100_000
    end

    test "five packages get the same flat allowance, not five times it" do
      # Decided by product: choosing several packages still gives one 100,000
      # allowance. Summing per package is the thing this pins against.
      items = Enum.map(Bundle.Package.slugs(), &item(&1, :package))

      {:ok, attrs} = Resolver.resolve(items, @snapshot)

      assert attrs.api_call_limits["month"] == 100_000
      assert length(attrs.packages) == 5
    end

    test "an add-on tier is added on top" do
      {:ok, attrs} =
        Resolver.resolve(
          [item("market", :package), item("api_calls_500k", :api_calls)],
          @snapshot
        )

      assert attrs.api_call_limits["month"] == 600_000
    end

    test "several units of an add-on multiply" do
      {:ok, attrs} =
        Resolver.resolve(
          [item("market", :package), item("api_calls_500k", :api_calls, 3)],
          @snapshot
        )

      assert attrs.api_call_limits["month"] == 1_600_000
    end

    test "burst limits never grow with the number of packages" do
      # Rate limits protect infrastructure rather than pricing data, so buying
      # more must not raise them.
      {:ok, one_package} = Resolver.resolve([item("market", :package)], @snapshot)

      {:ok, everything} =
        Resolver.resolve(
          Enum.map(Bundle.Package.slugs(), &item(&1, :package)) ++
            [item("api_calls_500k", :api_calls, 2)],
          @snapshot
        )

      assert one_package.api_call_limits["hour"] == 30_000
      assert one_package.api_call_limits["minute"] == 600
      assert everything.api_call_limits["hour"] == one_package.api_call_limits["hour"]
      assert everything.api_call_limits["minute"] == one_package.api_call_limits["minute"]
    end
  end

  describe "resolve/2 - data windows" do
    test "every bundle gets full history and realtime data" do
      {:ok, attrs} = Resolver.resolve([item("market", :package)], @snapshot)

      assert attrs.historical_data_in_days == nil
      assert attrs.realtime_data_cut_off_in_days == 0
    end
  end

  describe "resolve/2 - refusals" do
    test "refuses a subscription with no package at all" do
      # An entitlement granting nothing looks identical to a working one
      # everywhere downstream, and would present as a paying customer whose every
      # request is refused.
      assert {:error, message} = Resolver.resolve([], @snapshot)
      assert message =~ "at least one package"
    end

    test "refuses add-on calls with no package behind them" do
      assert {:error, message} =
               Resolver.resolve([item("api_calls_500k", :api_calls)], @snapshot)

      assert message =~ "at least one package"
    end

    test "refuses an unknown package" do
      assert {:error, message} = Resolver.resolve([item("premium", :package)], @snapshot)
      assert message =~ "premium"
    end

    test "refuses an unknown add-on tier" do
      assert {:error, message} =
               Resolver.resolve(
                 [item("market", :package), item("api_calls_1m", :api_calls)],
                 @snapshot
               )

      assert message =~ "api_calls_1m"
    end

    test "a package missing from an older snapshot grants nothing but does not fail" do
      # A snapshot published before a package existed genuinely has no list for
      # it. The fix is re-resolving against a newer snapshot, not raising here.
      older = %PackageSnapshot{version: 1, contents: %{"market" => ["price_usd"]}}

      {:ok, attrs} =
        Resolver.resolve([item("market", :package), item("social", :package)], older)

      assert attrs.metric_access["accessible"] == ["price_usd"]
      assert attrs.packages == ["market", "social"]
    end
  end

  describe "sync/1" do
    setup context do
      Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

      plan =
        insert(:plan_pro,
          id: 9400,
          name: @bundle_plan,
          product_id: context.product_api.id,
          amount: 0,
          stripe_id: "stripe_plan_" <> Ecto.UUID.generate()
        )

      subscription =
        insert(:subscription_pro,
          user_id: insert(:user).id,
          plan_id: plan.id,
          stripe_id: "sub_" <> Ecto.UUID.generate()
        )

      %{plan: plan, subscription: subscription}
    end

    test "writes the resolved entitlement onto the subscription", %{subscription: subscription} do
      publish_snapshot()
      buy(subscription, "market", :package)
      buy(subscription, "social", :package)

      assert {:ok, _} = Resolver.sync(subscription)

      stored = Repo.get!(Subscription, subscription.id).bundle_entitlement

      assert stored.packages == ["market", "social"]
      assert stored.api_call_limits["month"] == 100_000
      assert stored.package_snapshot_version == PackageSnapshot.latest().version
    end

    test "the stored entitlement is what answers access checks", %{subscription: subscription} do
      publish_snapshot()
      buy(subscription, "market", :package)

      {:ok, _} = Resolver.sync(subscription)

      entitlement = Repo.get!(Subscription, subscription.id).bundle_entitlement

      assert AccessChecker.plan_has_access?(
               {:metric, "bundle_test_price"},
               "SANAPI",
               @bundle_plan,
               entitlement
             )

      refute AccessChecker.plan_has_access?(
               {:metric, "bundle_test_dev_activity"},
               "SANAPI",
               @bundle_plan,
               entitlement
             )

      # Queries and signals stay reachable, as they are for everyone today.
      assert AccessChecker.plan_has_access?(
               {:query, :get_trending_words},
               "SANAPI",
               @bundle_plan,
               entitlement
             )
    end

    test "running it twice changes nothing", %{subscription: subscription} do
      # One item change in Stripe fires several subscription.updated events, so
      # this has to be safe to repeat.
      publish_snapshot()
      buy(subscription, "market", :package)

      {:ok, first} = Resolver.sync(subscription)
      {:ok, second} = Resolver.sync(Repo.get!(Subscription, subscription.id))

      assert first.bundle_entitlement == second.bundle_entitlement
    end

    test "dropping a package removes what it granted", %{subscription: subscription} do
      publish_snapshot()
      buy(subscription, "market", :package)
      social_item = buy(subscription, "social", :package)

      {:ok, _} = Resolver.sync(subscription)

      entitlement = Repo.get!(Subscription, subscription.id).bundle_entitlement
      assert "bundle_test_social_volume" in entitlement.metric_access["accessible"]

      Repo.delete!(social_item)
      {:ok, _} = Resolver.sync(Repo.get!(Subscription, subscription.id))

      entitlement = Repo.get!(Subscription, subscription.id).bundle_entitlement

      assert entitlement.packages == ["market"]
      refute "bundle_test_social_volume" in entitlement.metric_access["accessible"]
    end

    test "adding an add-on raises only the monthly allowance", %{subscription: subscription} do
      publish_snapshot()
      buy(subscription, "market", :package)
      {:ok, _} = Resolver.sync(subscription)

      buy(subscription, "api_calls_500k", :api_calls)
      {:ok, _} = Resolver.sync(Repo.get!(Subscription, subscription.id))

      limits =
        Bundle.Access.api_call_limits(Repo.get!(Subscription, subscription.id).bundle_entitlement)

      assert limits == %{month: 600_000, hour: 30_000, minute: 600}
    end

    test "refuses when no snapshot has been published", %{subscription: subscription} do
      buy(subscription, "market", :package)

      assert {:error, message} = Resolver.sync(subscription)
      assert message =~ "No bundle package snapshot"
      assert Repo.get!(Subscription, subscription.id).bundle_entitlement == nil
    end

    test "refuses a subscription with no items, leaving the row untouched", %{
      subscription: subscription
    } do
      publish_snapshot()

      assert {:error, message} = Resolver.sync(subscription)
      assert message =~ "at least one package"
      assert Repo.get!(Subscription, subscription.id).bundle_entitlement == nil
    end

    test "reports a missing subscription rather than raising" do
      assert {:error, message} = Resolver.sync(-1)
      assert message =~ "No subscription"
    end
  end

  defp buy(subscription, sku, type) do
    {:ok, item} = Item.create(%{subscription_id: subscription.id, sku: sku, type: type})
    item
  end

  # A small real snapshot: two categorized metrics in two different packages, so
  # the union and the exclusion are both observable.
  defp publish_snapshot do
    categories =
      Bundle.Package.all()
      |> Enum.with_index()
      |> Map.new(fn {package, index} ->
        {:ok, category} =
          Sanbase.Metric.Category.MetricCategory.create(%{
            name: package.category,
            display_order: index
          })

        {package.slug, category}
      end)

    categorize("bundle_test_price", categories["market"])
    categorize("bundle_test_social_volume", categories["social"])
    categorize("bundle_test_dev_activity", categories["development"])

    {:ok, snapshot} = PackageSnapshot.publish()
    snapshot
  end

  defp categorize(metric, category) do
    registry = Sanbase.MetricRegistryHelpers.create_registry_metric(metric)

    {:ok, _} =
      Sanbase.Metric.Category.MetricCategoryMapping.create(%{
        metric_registry_id: registry.id,
        category_id: category.id
      })
  end
end
