defmodule Sanbase.Billing.Plan.Bundle.LifecycleTest do
  use Sanbase.DataCase, async: false

  import Ecto.Query
  import Mock
  import Sanbase.Factory

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.{Catalog, Lifecycle, Package, PackageSnapshot, Price}
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  setup context do
    insert(:role_san_team)
    categorize_metrics()
    {:ok, _} = PackageSnapshot.publish(notes: "lifecycle test")
    {:ok, _} = Catalog.ensure_local_catalog()

    # Mark packages sellable without Stripe sync
    for sku <- ["market", "social", "development"], interval <- ["month", "year"] do
      from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
      |> Repo.update_all(
        set: [
          stripe_price_id: "price_#{sku}_#{interval}",
          amount: 35_000
        ]
      )
    end

    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9600")

    for {interval, id} <- [{"month", 9601}, {"year", 9602}] do
      case Plan.bundle_plan(interval) do
        nil ->
          insert(:plan_pro,
            id: id,
            name: "BUNDLE",
            product_id: context.product_api.id,
            interval: interval,
            amount: 0,
            is_private: true,
            stripe_id: "plan_bundle_#{interval}_" <> Ecto.UUID.generate()
          )

        %Plan{} = plan ->
          plan
          |> Plan.changeset(%{is_private: true})
          |> Repo.update!()
      end
    end

    user =
      insert(:user, stripe_customer_id: "cus_lifecycle_" <> Ecto.UUID.generate())

    %{user: user}
  end

  test "rejects subscribe when offering is legacy and user is not team", %{user: user} do
    assert {:error, "Bundle plans are not available for purchase yet"} =
             Lifecycle.subscribe(user, packages: ["market"], interval: "month")
  end

  test "subscribe creates items and entitlement for team in legacy mode", %{user: user} do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks(["price_market_month"]) do
      assert {:ok, sub} =
               Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert Plan.type(sub.plan.name) == :bundle
      assert sub.bundle_entitlement != nil

      items = Item.by_subscription(sub.id)
      assert Enum.map(items, & &1.sku) == ["market"]
    end
  end

  test "auto-replaces BUSINESS_PRO after successful subscribe", %{user: user} = context do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    legacy =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: context.plans.plan_business_pro_monthly.id,
        status: :active,
        stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
      )

    with_mocks stripe_mocks(["price_market_month"], cancel_legacy: true) do
      assert {:ok, sub} =
               Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert Plan.type(sub.plan.name) == :bundle
      assert Repo.reload!(legacy).status == :canceled
    end
  end

  test "rejects second bundle subscribe", %{user: user} do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks(["price_market_month"]) do
      assert {:ok, _} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert {:error, "You already have an active SanAPI subscription on the new offering"} =
               Lifecycle.subscribe(user, packages: ["social"], interval: "month")
    end
  end

  test "rejects CUSTOM auto-replace", %{user: user} = context do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    {:ok, custom} =
      %Plan{}
      |> Plan.changeset(%{
        name: "CUSTOM_ACME",
        product_id: context.product_api.id,
        amount: 100_000,
        currency: "USD",
        interval: "month",
        is_private: true,
        stripe_id: "plan_custom_" <> Ecto.UUID.generate()
      })
      |> Repo.insert()

    insert(:subscription_pro,
      user_id: user.id,
      plan_id: custom.id,
      status: :active,
      stripe_id: "sub_custom_" <> Ecto.UUID.generate()
    )

    assert {:error, "Active custom/enterprise SanAPI subscription cannot be auto-replaced"} =
             Lifecycle.subscribe(user, packages: ["market"], interval: "month")
  end

  test "add_item and remove_item (period-end flag)", %{user: user} do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks(["price_market_month", "price_social_month"]) do
      assert {:ok, sub} =
               Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert {:ok, sub} = Lifecycle.add_item(user, sub.id, "social")
      assert Enum.sort(Enum.map(Item.by_subscription(sub.id), & &1.sku)) == ["market", "social"]

      assert {:ok, sub} = Lifecycle.remove_item(user, sub.id, "social")
      social = Enum.find(Item.by_subscription(sub.id), &(&1.sku == "social"))
      assert social.cancel_at_period_end
    end
  end

  test "upgrade_downgrade rejects bundle subscriptions", %{user: user} = context do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks(["price_market_month"]) do
      assert {:ok, sub} =
               Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert {:error, msg} =
               StripeApi.upgrade_downgrade(sub, context.plans.plan_business_max_monthly)

      assert msg =~ "Bundle subscriptions cannot use upgrade/downgrade"
    end
  end

  defp stripe_mocks(price_ids, opts \\ []) do
    cancel_legacy? = Keyword.get(opts, :cancel_legacy, false)

    base = [
      {StripeApi, [:passthrough],
       [
         create_bundle_subscription: fn params ->
           ids =
             params.items
             |> Enum.map(fn
               %{price: id} -> id
               _ -> nil
             end)
             |> Enum.reject(&is_nil/1)

           StripeApiTestResponse.create_bundle_subscription_resp(price_ids: ids)
         end,
         create_subscription_item: fn _sub, price_id, _opts ->
           StripeApiTestResponse.create_subscription_item_resp(price_id: price_id)
         end,
         update_subscription: fn _id, _params ->
           StripeApiTestResponse.update_subscription_resp(price_ids: price_ids)
         end,
         cancel_subscription_at_period_end: fn id ->
           StripeApiTestResponse.update_subscription_resp(stripe_id: id)
         end
       ]}
    ]

    if cancel_legacy? do
      [
        {StripeApi, [:passthrough],
         [
           create_bundle_subscription: fn params ->
             ids = Enum.map(params.items, & &1.price)
             StripeApiTestResponse.create_bundle_subscription_resp(price_ids: ids)
           end,
           create_subscription_item: fn _sub, price_id, _opts ->
             StripeApiTestResponse.create_subscription_item_resp(price_id: price_id)
           end,
           update_subscription: fn _id, _params ->
             StripeApiTestResponse.update_subscription_resp(price_ids: price_ids)
           end,
           cancel_subscription_with_proration: fn id ->
             StripeApiTestResponse.cancel_subscription_with_proration_resp(stripe_id: id)
           end,
           cancel_subscription_at_period_end: fn id ->
             StripeApiTestResponse.update_subscription_resp(stripe_id: id)
           end
         ]}
      ]
    else
      base
    end
  end

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
            module: "Sanbase.Metric.BundleLifecycleTestAdapter",
            metric: metric,
            category_id: category.id
          })
      end
    end
  end
end
