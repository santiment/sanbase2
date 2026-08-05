defmodule SanbaseWeb.Graphql.BundleMutationsApiTest do
  @moduledoc ~s"""
  The five bundle mutations and the catalog query over real GraphQL requests.

  The lifecycle unit tests prove what the operations do. These prove the layer
  above: that the mutations exist under the names the frontend was given, that
  they authenticate, that one account cannot act on another's subscription, and
  that a refusal reaches the caller as a message rather than as a crash or as
  somebody else's data.
  """

  use SanbaseWeb.ConnCase, async: false

  import Ecto.Query
  import Mock
  import Sanbase.Factory
  import SanbaseWeb.Graphql.TestHelpers

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.{Catalog, PackageSnapshot, Price}
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  @moduletag capture_log: true

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
    {:ok, _} = PackageSnapshot.publish(notes: "bundle mutations test")
    {:ok, _} = Catalog.ensure_local_catalog()

    for sku <- ["market", "social", "development"], interval <- ["month", "year"] do
      from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
      |> Repo.update_all(set: [stripe_price_id: "price_#{sku}_#{interval}", amount: 35_000])
    end

    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9903")

    for {interval, id} <- [{"month", 9901}, {"year", 9902}] do
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
          plan |> Plan.changeset(%{is_private: true}) |> Repo.update!()
      end
    end

    user = insert(:user, stripe_customer_id: "cus_api_" <> Ecto.UUID.generate())
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    %{user: user, conn: setup_jwt_auth(build_conn(), user)}
  end

  describe "bundleCatalog" do
    test "is refused for an anonymous caller while the offering is private" do
      error = execute_query_with_error(build_conn(), catalog_query("MONTH"), "bundleCatalog")

      assert error =~ "not available"
    end

    test "lists the sellable prices for a team member", %{conn: conn} do
      prices = execute_query(conn, catalog_query("MONTH"), "bundleCatalog")

      skus = prices |> Enum.map(& &1["sku"]) |> Enum.sort()
      assert "market" in skus
      assert "social" in skus

      market = Enum.find(prices, &(&1["sku"] == "market"))
      assert market["amount"] == 35_000
      assert market["interval"] == "MONTH"
      assert market["stripePriceId"] == "price_market_month"
    end
  end

  describe "subscribeBundle" do
    test "requires authentication" do
      error =
        execute_mutation_with_error(
          build_conn(),
          subscribe_mutation(["market"], "MONTH")
        )

      assert error =~ "unauthorized" or error =~ "not logged in"
    end

    test "buys a bundle and returns the subscription", %{conn: conn} do
      with_mocks stripe_mocks() do
        result =
          execute_mutation(conn, subscribe_mutation(["market"], "MONTH"), "subscribeBundle")

        assert result["status"] == "ACTIVE"
        assert result["plan"]["name"] == "BUNDLE"
        assert result["plan"]["interval"] == "month"
      end
    end

    test "reports an unknown package as a message", %{conn: conn} do
      with_mocks stripe_mocks() do
        error =
          execute_mutation_with_error(conn, subscribe_mutation(["not_a_package"], "MONTH"))

        assert error =~ "is not sellable"
      end
    end
  end

  describe "managing an existing bundle" do
    setup %{conn: conn} do
      with_mocks stripe_mocks() do
        subscription =
          execute_mutation(
            conn,
            subscribe_mutation(["market", "social"], "MONTH"),
            "subscribeBundle"
          )

        %{subscription_id: String.to_integer(subscription["id"])}
      end
    end

    test "addBundleItem adds a package", %{conn: conn, subscription_id: id} do
      with_mocks stripe_mocks() do
        result =
          execute_mutation(
            conn,
            item_mutation("addBundleItem", id, "development"),
            "addBundleItem"
          )

        assert result["id"] == to_string(id)
        assert "development" in Enum.map(Item.by_subscription(id), & &1.sku)
      end
    end

    test "removeBundleItem schedules a package for removal", %{conn: conn, subscription_id: id} do
      with_mocks stripe_mocks() do
        _result =
          execute_mutation(
            conn,
            item_mutation("removeBundleItem", id, "social"),
            "removeBundleItem"
          )

        social = Enum.find(Item.by_subscription(id), &(&1.sku == "social"))
        assert social.remove_at != nil
      end
    end

    test "switchBundleInterval moves the plan", %{conn: conn, subscription_id: id} do
      with_mocks stripe_mocks() do
        result =
          execute_mutation(
            conn,
            """
            mutation {
              switchBundleInterval(subscriptionId: #{id}) {
                id
                plan { name interval }
              }
            }
            """,
            "switchBundleInterval"
          )

        assert result["plan"]["interval"] == "year"
      end
    end

    test "cancelBundleSubscription schedules cancellation", %{conn: conn, subscription_id: id} do
      with_mocks stripe_mocks() do
        result =
          execute_mutation(
            conn,
            """
            mutation {
              cancelBundleSubscription(subscriptionId: #{id}) {
                isScheduledForCancellation
                scheduledForCancellationAt
              }
            }
            """,
            "cancelBundleSubscription"
          )

        assert result["isScheduledForCancellation"] == true
      end
    end

    test "another account cannot manage the subscription", %{subscription_id: id} do
      other = insert(:user)
      {:ok, _} = UserRole.create(other.id, Role.san_team_role_id())
      other_conn = setup_jwt_auth(build_conn(), other)

      with_mocks stripe_mocks() do
        error =
          execute_mutation_with_error(
            other_conn,
            item_mutation("addBundleItem", id, "development")
          )

        assert error =~ "does not belong to the user"
      end
    end

    test "a changeset failure is not reported to the caller verbatim", %{
      conn: conn,
      subscription_id: id
    } do
      # `market` is already on the subscription, so the insert violates the unique
      # index. The caller gets a sentence, not Ecto's error list.
      with_mocks stripe_mocks() do
        error = execute_mutation_with_error(conn, item_mutation("addBundleItem", id, "market"))

        refute error =~ "constraint"
        refute error =~ "Ecto"
      end
    end
  end

  # --- helpers ---

  defp catalog_query(interval) do
    """
    {
      bundleCatalog(interval: #{interval}) {
        sku
        type
        interval
        amount
        currency
        stripePriceId
      }
    }
    """
  end

  defp subscribe_mutation(packages, interval) do
    packages = packages |> Enum.map(&~s("#{&1}")) |> Enum.join(", ")

    """
    mutation {
      subscribeBundle(packages: [#{packages}], interval: #{interval}, paymentMethodId: "pm_test") {
        id
        status
        plan { name interval }
      }
    }
    """
  end

  defp item_mutation(name, subscription_id, sku) do
    """
    mutation {
      #{name}(subscriptionId: #{subscription_id}, sku: "#{sku}") {
        id
        status
        plan { name interval }
      }
    }
    """
  end

  defp stripe_mocks do
    [
      {StripeApi, [:passthrough],
       [
         attach_payment_method_to_customer: fn user, _payment_method_id -> {:ok, user} end,
         create_bundle_subscription: fn params ->
           price_ids = Enum.map(params.items, & &1.price)
           stripe_id = "sub_api_" <> Integer.to_string(System.unique_integer([:positive]))
           remember_prices(stripe_id, price_ids)

           StripeApiTestResponse.create_bundle_subscription_resp(
             stripe_id: stripe_id,
             price_ids: price_ids
           )
           |> with_stable_item_ids()
         end,
         create_subscription_item: fn subscription_id, price_id, _opts ->
           StripeApiTestResponse.create_subscription_item_resp(
             id: "si_" <> price_id,
             price_id: price_id,
             subscription: subscription_id
           )
         end,
         update_subscription: fn stripe_id, params ->
           price_ids =
             case Map.get(params, :items) do
               nil ->
                 remembered_prices(stripe_id)

               items ->
                 items
                 |> Enum.reject(&Map.get(&1, :deleted, false))
                 |> Enum.map(& &1.price)
             end

           remember_prices(stripe_id, price_ids)

           StripeApiTestResponse.update_subscription_resp(
             stripe_id: stripe_id,
             price_ids: price_ids
           )
           |> with_stable_item_ids()
         end,
         cancel_subscription_at_period_end: fn stripe_id ->
           {:ok, stripe_sub} =
             StripeApiTestResponse.update_subscription_resp(
               stripe_id: stripe_id,
               price_ids: remembered_prices(stripe_id)
             )

           {:ok, %{stripe_sub | cancel_at_period_end: true}}
         end
       ]}
    ]
  end

  defp with_stable_item_ids({:ok, %Stripe.Subscription{items: %Stripe.List{} = list} = sub}) do
    data = Enum.map(list.data, fn item -> %{item | id: "si_" <> item.price.id} end)

    {:ok, %{sub | items: %{list | data: data}}}
  end

  defp remember_prices(stripe_id, price_ids) do
    Process.put({:stripe_prices, stripe_id}, price_ids)
  end

  defp remembered_prices(stripe_id), do: Process.get({:stripe_prices, stripe_id}, [])

  defp categorize_metrics do
    for {package, index} <- Enum.with_index(Sanbase.Billing.Plan.Bundle.Package.all()) do
      {:ok, category} =
        case Repo.get_by(MetricCategory, name: package.category) do
          nil -> MetricCategory.create(%{name: package.category, display_order: index})
          cat -> {:ok, cat}
        end

      metric = Map.fetch!(@packaged_metrics, package.slug)

      unless Repo.get_by(MetricCategoryMapping, metric: metric) do
        {:ok, _} =
          MetricCategoryMapping.create(%{
            module: "Sanbase.Metric.BundleMutationsApiTestAdapter",
            metric: metric,
            category_id: category.id
          })
      end
    end
  end
end
