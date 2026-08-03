defmodule Sanbase.Billing.Plan.Bundle.SubscriptionItemsTest do
  @moduledoc ~s"""
  What a bundle customer bought, and what the sellable things cost.

  The guarantees worth pinning here are the ones whose absence fails quietly:

    * a SKU that does not name a real package or add-on must be rejected on the
      way in, because stored it would contribute nothing when the entitlement is
      worked out - a paying customer receiving less, with no error anywhere
    * the same package cannot be bought twice on one subscription
    * a `BUNDLE` marker plan must never appear on the public plan list
  """

  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.Price
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Repo

  setup context do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9001")

    plan =
      insert(:plan_pro,
        id: 9300,
        name: "BUNDLE",
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

  describe "subscription items" do
    test "record the packages and add-ons that were bought", %{subscription: subscription} do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: "market", type: :package})

      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: "social", type: :package})

      {:ok, _} =
        Item.create(%{
          subscription_id: subscription.id,
          sku: "api_calls_500k",
          type: :api_calls,
          quantity: 2
        })

      items = Item.by_subscription(subscription.id)

      assert Enum.map(items, & &1.sku) == ["market", "social", "api_calls_500k"]
      assert Enum.map(items, & &1.type) == [:package, :package, :api_calls]
    end

    test "are reachable from the subscription", %{subscription: subscription} do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: "market", type: :package})

      loaded = Repo.get!(Subscription, subscription.id) |> Repo.preload(:items)

      assert Enum.map(loaded.items, & &1.sku) == ["market"]
    end

    test "a legacy subscription has none", %{plan: plan} do
      legacy = insert(:subscription_pro, user_id: insert(:user).id, plan_id: plan.id)

      assert Item.by_subscription(legacy.id) == []
    end

    test "reject a package that is not sold", %{subscription: subscription} do
      assert {:error, changeset} =
               Item.create(%{subscription_id: subscription.id, sku: "onchain", type: :package})

      assert hd(errors_on(changeset).sku) =~ "Unknown package"
      # The message lists what is sold, so a typo is fixable without opening the
      # definitions module.
      assert hd(errors_on(changeset).sku) =~ "onchain_core"
    end

    test "reject an add-on tier that is not sold", %{subscription: subscription} do
      assert {:error, changeset} =
               Item.create(%{
                 subscription_id: subscription.id,
                 sku: "api_calls_1m",
                 type: :api_calls
               })

      assert hd(errors_on(changeset).sku) =~ "Unknown API call add-on"
    end

    test "reject the same package twice on one subscription", %{subscription: subscription} do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: "market", type: :package})

      assert {:error, changeset} =
               Item.create(%{subscription_id: subscription.id, sku: "market", type: :package})

      assert "is already an item on this subscription" in errors_on(changeset).subscription_id
    end

    test "allow the same package on two different subscriptions", %{plan: plan} do
      other =
        insert(:subscription_pro,
          user_id: insert(:user).id,
          plan_id: plan.id,
          stripe_id: "sub_" <> Ecto.UUID.generate()
        )

      another =
        insert(:subscription_pro,
          user_id: insert(:user).id,
          plan_id: plan.id,
          stripe_id: "sub_" <> Ecto.UUID.generate()
        )

      assert {:ok, _} = Item.create(%{subscription_id: other.id, sku: "market", type: :package})
      assert {:ok, _} = Item.create(%{subscription_id: another.id, sku: "market", type: :package})
    end

    test "reject a package quantity above one", %{subscription: subscription} do
      # Owning Market twice means nothing. Silently ignoring the quantity would
      # let a customer be billed twice for one thing.
      assert {:error, changeset} =
               Item.create(%{
                 subscription_id: subscription.id,
                 sku: "market",
                 type: :package,
                 quantity: 2
               })

      assert "must be 1 for a package item" in errors_on(changeset).quantity
    end

    test "leave a missing SKU to the required-field check", %{subscription: subscription} do
      # One clear message, not two. Without the nil short-circuit in validate_sku/1
      # this also reported "must be a string, got nil", which describes a type
      # problem rather than the actual one.
      assert {:error, changeset} =
               Item.create(%{subscription_id: subscription.id, type: :package})

      assert errors_on(changeset).sku == ["can't be blank"]
    end

    test "reject a quantity of zero", %{subscription: subscription} do
      assert {:error, changeset} =
               Item.create(%{
                 subscription_id: subscription.id,
                 sku: "api_calls_500k",
                 type: :api_calls,
                 quantity: 0
               })

      assert errors_on(changeset).quantity != []
    end

    test "are deleted with the subscription", %{subscription: subscription} do
      {:ok, _} = Item.create(%{subscription_id: subscription.id, sku: "market", type: :package})

      Repo.delete!(subscription)

      assert Item.by_subscription(subscription.id) == []
    end
  end

  describe "the price catalog" do
    test "holds a row per SKU per interval" do
      {:ok, _} =
        Price.create(%{sku: "market", type: :package, interval: "month", amount: 9900})

      {:ok, _} =
        Price.create(%{sku: "market", type: :package, interval: "year", amount: 99_000})

      assert Enum.map(Price.active("month"), & &1.amount) == [9900]
      assert Enum.map(Price.active("year"), & &1.amount) == [99_000]
    end

    test "accepts a row with no decided price yet" do
      # Prices are not final. A row with no amount says "this is sold, the price
      # is still open" rather than forcing a placeholder that could be charged.
      assert {:ok, price} = Price.create(%{sku: "social", type: :package, interval: "month"})

      assert price.amount == nil
      assert price in Price.active("month")
      assert Price.sellable("month") == []
    end

    test "only counts a row as sellable once it has both a price and a Stripe price id" do
      {:ok, _} =
        Price.create(%{
          sku: "market",
          type: :package,
          interval: "month",
          amount: 9900,
          stripe_price_id: "price_" <> Ecto.UUID.generate()
        })

      {:ok, _} = Price.create(%{sku: "social", type: :package, interval: "month", amount: 4900})

      assert Enum.map(Price.sellable("month"), & &1.sku) == ["market"]
    end

    test "rejects an unknown SKU" do
      assert {:error, changeset} =
               Price.create(%{sku: "enterprise", type: :package, interval: "month"})

      assert hd(errors_on(changeset).sku) =~ "Unknown package"
    end

    test "rejects an interval Stripe cannot bill" do
      assert {:error, changeset} =
               Price.create(%{sku: "market", type: :package, interval: "week"})

      assert errors_on(changeset).interval != []
    end

    test "allows only one active price per SKU and interval" do
      {:ok, _} = Price.create(%{sku: "market", type: :package, interval: "month", amount: 9900})

      assert {:error, changeset} =
               Price.create(%{sku: "market", type: :package, interval: "month", amount: 10_900})

      assert "already has an active price for this interval" in errors_on(changeset).sku
    end

    test "replacing a price keeps the old row and deactivates it" do
      # Stripe Prices are immutable, so a change is a new row plus an archived
      # old one. Keeping the old row means an invoice raised at the old price can
      # still be explained.
      {:ok, old} = Price.create(%{sku: "market", type: :package, interval: "month", amount: 9900})

      assert {:ok, new} =
               Price.replace(%{
                 sku: "market",
                 type: :package,
                 interval: "month",
                 amount: 12_900
               })

      assert Enum.map(Price.active("month"), & &1.amount) == [12_900]
      refute Repo.get!(Price, old.id).is_active
      assert Repo.get!(Price, new.id).is_active
    end
  end

  describe "the BUNDLE marker plan" do
    test "is never offered on the public plan list", %{plan: plan} do
      # A $0 plan on the pricing page, and one that `subscribe(plan_id:)` cannot
      # correctly create, is worse than not listing it.
      {:ok, products} = Plan.product_with_plans()

      listed = Enum.flat_map(products, fn product -> Enum.map(product.plans, & &1.name) end)

      refute plan.name in listed
      assert "PRO" in listed
    end

    test "is still classified as a bundle and usable as a subscription's plan", %{
      plan: plan,
      subscription: subscription
    } do
      assert Plan.type(Plan.plan_name(plan)) == :bundle
      assert Repo.get!(Subscription, subscription.id).plan_id == plan.id
    end
  end
end
