defmodule Sanbase.Billing.Plan.Bundle.ItemExpiryTest do
  use Sanbase.DataCase, async: false

  import Ecto.Query
  import Mock
  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan

  alias Sanbase.Billing.Plan.Bundle.{
    Catalog,
    ItemExpiry,
    Package,
    PackageSnapshot,
    Price,
    Resolver
  }

  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo
  alias Sanbase.StripeApi

  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup context do
    categorize_metrics()
    {:ok, _} = PackageSnapshot.publish(notes: "item expiry test")
    {:ok, _} = Catalog.ensure_local_catalog()

    for sku <- ["market", "social"], interval <- ["month", "year"] do
      from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
      |> Repo.update_all(set: [stripe_price_id: "price_#{sku}_#{interval}", amount: 35_000])
    end

    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9700")

    plan =
      case Plan.bundle_plan("month") do
        %Plan{} = plan ->
          plan

        nil ->
          insert(:plan_pro,
            id: 9701,
            name: "BUNDLE",
            product_id: context.product_api.id,
            interval: "month",
            amount: 0,
            is_private: true,
            stripe_id: "plan_bundle_month_" <> Ecto.UUID.generate()
          )
      end

    user = insert(:user, stripe_customer_id: "cus_expiry_" <> Ecto.UUID.generate())

    subscription =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: plan.id,
        status: :active,
        stripe_id: "sub_expiry_" <> Ecto.UUID.generate(),
        current_period_end:
          DateTime.utc_now() |> DateTime.add(30, :day) |> DateTime.truncate(:second)
      )

    for {sku, stripe_item_id} <- [{"market", "si_market"}, {"social", "si_social"}] do
      {:ok, _} =
        Item.create(%{
          subscription_id: subscription.id,
          stripe_item_id: stripe_item_id,
          sku: sku,
          type: :package,
          quantity: 1
        })
    end

    {:ok, subscription} = Resolver.sync(subscription.id)

    %{user: user, subscription: subscription}
  end

  test "leaves alone an item whose deadline has not arrived", %{subscription: subscription} do
    schedule_removal("social", subscription, DateTime.add(DateTime.utc_now(), 5, :day))

    with_mock StripeApi, [:passthrough], delete_subscription_item: &record_delete/2 do
      assert %{removed: 0, failed: 0} = ItemExpiry.run()

      assert deletes() == []
      assert Enum.map(items(subscription), & &1.sku) == ["market", "social"]
    end
  end

  test "removes an item whose deadline has passed", %{subscription: subscription} = context do
    schedule_removal("social", subscription, DateTime.add(DateTime.utc_now(), -1, :second))

    with_mock StripeApi, [:passthrough], delete_subscription_item: &record_delete/2 do
      assert %{removed: 1, failed: 0} = ItemExpiry.run()

      # Told Stripe, so the next invoice is smaller. No proration: the period the
      # customer paid for was served in full.
      assert [{"si_social", opts}] = deletes()
      assert Keyword.get(opts, :proration_behavior) == "none"

      assert Enum.map(items(subscription), & &1.sku) == ["market"]

      # And the entitlement no longer grants it.
      reloaded = Subscription.by_id(subscription.id)
      assert reloaded.bundle_entitlement.packages == ["market"]

      refute "social_volume_total" in reloaded.bundle_entitlement.metric_access["accessible"]

      # The quota row is rewritten off the new entitlement rather than left stale.
      acl = Repo.get_by(ApiCallLimit, user_id: context.user.id)
      assert acl.resolved_api_call_limits["month"] > 0
    end
  end

  test "treats an item already gone from Stripe as removed", %{subscription: subscription} do
    schedule_removal("social", subscription, DateTime.add(DateTime.utc_now(), -1, :second))

    missing = fn _id, _opts ->
      {:error,
       %Stripe.Error{
         source: :stripe,
         code: :resource_missing,
         message: "No such subscription item"
       }}
    end

    with_mock StripeApi, [:passthrough], delete_subscription_item: missing do
      assert %{removed: 1, failed: 0} = ItemExpiry.run()
      assert Enum.map(items(subscription), & &1.sku) == ["market"]
    end
  end

  test "keeps the row when Stripe refuses, so the next run retries",
       %{subscription: subscription} do
    schedule_removal("social", subscription, DateTime.add(DateTime.utc_now(), -1, :second))

    refuse = fn _id, _opts ->
      {:error, %Stripe.Error{source: :stripe, code: :api_error, message: "boom"}}
    end

    with_mock StripeApi, [:passthrough], delete_subscription_item: refuse do
      assert %{removed: 0, failed: 1} = ItemExpiry.run()
    end

    # Still there, still scheduled - nothing was silently dropped.
    social = Enum.find(items(subscription), &(&1.sku == "social"))
    assert social.remove_at != nil

    with_mock StripeApi, [:passthrough], delete_subscription_item: &record_delete/2 do
      assert %{removed: 1, failed: 0} = ItemExpiry.run()
      assert Enum.map(items(subscription), & &1.sku) == ["market"]
    end
  end

  test "an item that never reached Stripe is removed locally", %{subscription: subscription} do
    social = Enum.find(items(subscription), &(&1.sku == "social"))

    {:ok, _} =
      social
      |> Item.changeset(%{
        stripe_item_id: nil,
        remove_at: DateTime.utc_now() |> DateTime.add(-1, :second) |> DateTime.truncate(:second)
      })
      |> Repo.update()

    with_mock StripeApi, [:passthrough], delete_subscription_item: &record_delete/2 do
      assert %{removed: 1, failed: 0} = ItemExpiry.run()

      assert deletes() == []
      assert Enum.map(items(subscription), & &1.sku) == ["market"]
    end
  end

  # --- helpers ---

  defp schedule_removal(sku, subscription, remove_at) do
    item = Enum.find(items(subscription), &(&1.sku == sku))

    {:ok, item} =
      item
      |> Item.changeset(%{remove_at: DateTime.truncate(remove_at, :second)})
      |> Repo.update()

    item
  end

  defp items(subscription), do: Item.by_subscription(subscription.id)

  defp record_delete(stripe_item_id, opts) do
    Process.put(:deletes, [{stripe_item_id, opts} | Process.get(:deletes, [])])
    {:ok, %{id: stripe_item_id, deleted: true}}
  end

  defp deletes, do: Process.get(:deletes, []) |> Enum.reverse()

  defp categorize_metrics do
    for {package, index} <- Enum.with_index(Package.all()) do
      {:ok, category} =
        case Repo.get_by(MetricCategory, name: package.category) do
          nil -> MetricCategory.create(%{name: package.category, display_order: index})
          cat -> {:ok, cat}
        end

      metric = Map.fetch!(@packaged_metrics, package.slug)

      unless Repo.get_by(MetricCategoryMapping, metric: metric) do
        {:ok, _} =
          MetricCategoryMapping.create(%{
            module: "Sanbase.Metric.BundleItemExpiryTestAdapter",
            metric: metric,
            category_id: category.id
          })
      end
    end
  end
end
