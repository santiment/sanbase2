defmodule Sanbase.Billing.StripeEventBundleSyncTest do
  @moduledoc ~s"""
  Task WH: `customer.subscription.created|updated|deleted` for bundle
  subscriptions, and the backward-compatibility guarantee that the legacy
  single-item path is untouched.

  The legacy cases come first on purpose - they are the BC contract of §7.1, and
  the bundle branching is only correct if they still produce the same result.
  """

  use Sanbase.DataCase, async: false

  import ExUnit.CaptureLog
  import Mock
  import Sanbase.Factory

  alias Sanbase.ApiCallLimit
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.Catalog
  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Billing.Plan.Bundle.PackageSnapshot
  alias Sanbase.Billing.Plan.Bundle.Price
  alias Sanbase.Billing.StripeEvent
  alias Sanbase.Billing.Subscription
  alias Sanbase.Billing.Subscription.Item
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  # The metric each package must contain for the snapshot to be buildable - a
  # package that resolves to nothing refuses to be published.
  @packaged_metrics %{
    "market" => "price_usd",
    "development" => "dev_activity",
    "social" => "social_volume_total",
    "onchain_core" => "mvrv_usd",
    "onchain_labels" => "nvt"
  }

  @sellable_skus ["market", "social", "development"]

  # Fixed for the reconciliation block, so every Stripe snapshot in it describes
  # the same subscription.
  @reconciled_stripe_id "sub_bundle_reconciled"

  setup context do
    categorize_metrics()
    {:ok, _} = PackageSnapshot.publish(notes: "webhook test")
    {:ok, _} = Catalog.ensure_local_catalog()

    # Stripe price ids without going anywhere near Stripe. Deterministic, so a
    # test can name the price an item is expected to carry.
    for sku <- @sellable_skus, interval <- ["month", "year"] do
      make_sellable(sku, interval)
    end

    insert_bundle_marker_plans(context.product_api.id)

    user = insert(:user, stripe_customer_id: "cus_" <> rand_hex_str(12))

    %{user: user}
  end

  # ────────────────────────────────────────────────────────────────────────────
  # BC: the legacy single-item path
  # ────────────────────────────────────────────────────────────────────────────

  describe "legacy single-item subscriptions are unaffected" do
    test "created binds the subscription to the plan behind item[0]", %{user: user} do
      stripe_sub = legacy_stripe_sub(customer: user.stripe_customer_id)

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.created", stripe_sub.id))
      end

      assert %Subscription{} = sub = Subscription.by_stripe_id(stripe_sub.id)
      assert sub.user_id == user.id
      # plan_pro carries the stripe_id the canned legacy item reports.
      assert sub.plan.name == "PRO"
      assert Item.by_subscription(sub.id) == []
      assert sub.bundle_entitlement == nil
    end

    test "created does not create a second subscription for a known stripe_id", %{user: user} do
      stripe_sub = legacy_stripe_sub(customer: user.stripe_customer_id)
      insert(:subscription_essential, user: user, stripe_id: stripe_sub.id)

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.created", stripe_sub.id))
      end

      assert Repo.aggregate(from(s in Subscription, where: s.user_id == ^user.id), :count) == 1
    end

    test "created without a matching plan leaves the event unprocessed", %{user: user} do
      stripe_sub = legacy_stripe_sub(customer: user.stripe_customer_id)

      Plan.by_stripe_id("plan_F5bv8ZRkhnAnmR")
      |> Plan.changeset(%{stripe_id: "non_existing"})
      |> Repo.update!()

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "Plan for subscription_id #{stripe_sub.id} does not exist"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
    end

    test "created without a matching customer leaves the event unprocessed" do
      stripe_sub = legacy_stripe_sub(customer: "cus_nobody_here")

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "Customer for subscription_id #{stripe_sub.id} does not exist"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
    end

    test "updated syncs status and period and touches no items", %{user: user} do
      sub =
        insert(:subscription_essential,
          user: user,
          stripe_id: "sub_legacy_" <> rand_hex_str(8),
          status: :active
        )

      stripe_sub =
        legacy_stripe_sub(
          stripe_id: sub.stripe_id,
          customer: user.stripe_customer_id,
          status: "past_due"
        )

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      synced = Subscription.by_stripe_id(sub.stripe_id)
      assert synced.status == :past_due
      # `fetch_plan_id/2` resolved item[0]'s plan, exactly as before.
      assert synced.plan.name == "PRO"
      assert Item.by_subscription(sub.id) == []
      assert synced.bundle_entitlement == nil
    end

    test "deleted marks the subscription canceled", %{user: user} do
      sub =
        insert(:subscription_essential,
          user: user,
          stripe_id: "sub_legacy_" <> rand_hex_str(8),
          status: :active
        )

      stripe_sub =
        legacy_stripe_sub(
          stripe_id: sub.stripe_id,
          customer: user.stripe_customer_id,
          status: "canceled"
        )

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.deleted", stripe_sub.id))
      end

      assert Subscription.by_stripe_id(sub.stripe_id).status == :canceled
    end

    test "updated for an unknown stripe_id leaves the event unprocessed", %{user: user} do
      stripe_sub = legacy_stripe_sub(customer: user.stripe_customer_id)

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.updated", stripe_sub.id))
          end)

        assert log =~ "Subscription with stripe_id: #{stripe_sub.id} does not exist"
      end
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # customer.subscription.created
  # ────────────────────────────────────────────────────────────────────────────

  describe "bundle customer.subscription.created" do
    test "resolves the entitlement and duplicates nothing when the row already exists",
         %{user: user} do
      stripe_sub =
        bundle_stripe_sub(customer: user.stripe_customer_id, skus: ["market", "social"])

      sub = seed_bundle_subscription(user, stripe_sub, ["market", "social"])

      # Deliberately left unresolved, so a passing assertion can only come from
      # the webhook having run the resolver.
      assert sub.bundle_entitlement == nil

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.created", stripe_sub.id))
      end

      assert Repo.aggregate(from(s in Subscription, where: s.user_id == ^user.id), :count) == 1

      resolved = Subscription.by_stripe_id(stripe_sub.id)
      assert resolved.plan.name == "BUNDLE"
      assert resolved.bundle_entitlement.packages == ["market", "social"]

      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) |> Enum.sort() == [
               "market",
               "social"
             ]
    end

    test "adopts a subscription that has no local row", %{user: user} do
      stripe_sub = bundle_stripe_sub(customer: user.stripe_customer_id, skus: ["market"])

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.created", stripe_sub.id))
      end

      assert %Subscription{} = sub = Subscription.by_stripe_id(stripe_sub.id)
      assert sub.user_id == user.id
      assert sub.plan.name == "BUNDLE"
      assert sub.plan.interval == "month"
      assert sub.bundle_entitlement.packages == ["market"]

      assert [%Item{} = item] = Item.by_subscription(sub.id)
      assert item.sku == "market"
      assert item.type == :package
      assert item.stripe_item_id == "si_price_market_month"
    end

    test "adopts a yearly subscription onto the yearly marker plan", %{user: user} do
      stripe_sub =
        bundle_stripe_sub(
          customer: user.stripe_customer_id,
          skus: ["market"],
          interval: "year"
        )

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.created", stripe_sub.id))
      end

      sub = Subscription.by_stripe_id(stripe_sub.id)
      assert sub.plan.name == "BUNDLE"
      assert sub.plan.interval == "year"
    end

    test "refuses to adopt when a price id is not in the bundle catalog", %{user: user} do
      stripe_sub =
        bundle_stripe_sub(
          customer: user.stripe_customer_id,
          skus: ["market"],
          extra_price_ids: ["price_mystery_thing"]
        )

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "cannot be adopted"
        assert log =~ "price_mystery_thing"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
      assert Repo.aggregate(from(i in Item), :count) == 0
      # Never invent a plans row for a package price (§7.3 #2).
      assert Plan.by_stripe_id("price_mystery_thing") == nil
      assert Plan.by_stripe_id("price_market_month") == nil
    end

    test "refuses to adopt with no package item", %{user: user} do
      make_sellable("api_calls_500k", "month")

      stripe_sub =
        bundle_stripe_sub(
          customer: user.stripe_customer_id,
          price_ids: ["price_api_calls_500k_month"]
        )

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "no package item"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
    end

    test "refuses to adopt without a published package snapshot", %{user: user} do
      Repo.delete_all(PackageSnapshot)
      stripe_sub = bundle_stripe_sub(customer: user.stripe_customer_id, skus: ["market"])

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "No bundle package snapshot has been published"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
    end

    test "refuses to adopt for an unknown Stripe customer" do
      stripe_sub = bundle_stripe_sub(customer: "cus_nobody_here", skus: ["market"])

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: false} =
                     process(event("customer.subscription.created", stripe_sub.id))
          end)

        assert log =~ "Customer for subscription_id #{stripe_sub.id} does not exist"
      end

      assert Subscription.by_stripe_id(stripe_sub.id) == nil
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # customer.subscription.updated - item reconciliation
  # ────────────────────────────────────────────────────────────────────────────

  describe "bundle customer.subscription.updated" do
    setup %{user: user} do
      stripe_sub = stripe_snapshot(user, ["market"])
      sub = seed_bundle_subscription(user, stripe_sub, ["market"])

      %{sub: sub, stripe_sub: stripe_sub}
    end

    test "adds an item that appeared in Stripe", %{user: user, sub: sub} do
      grown = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(grown) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", grown.id))
      end

      items = Item.by_subscription(sub.id)
      assert Enum.map(items, & &1.sku) |> Enum.sort() == ["market", "social"]

      social = Enum.find(items, &(&1.sku == "social"))
      assert social.type == :package
      assert social.stripe_item_id == "si_price_social_month"
      assert social.quantity == 1

      entitlement = Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement
      assert entitlement.packages == ["market", "social"]
      assert "social_volume_total" in entitlement.metric_access["accessible"]
    end

    test "deletes an item that is gone from Stripe", %{user: user, sub: sub} do
      {:ok, _} =
        Item.create(%{
          subscription_id: sub.id,
          sku: "social",
          type: :package,
          stripe_item_id: "si_price_social_month",
          quantity: 1
        })

      {:ok, _} = Sanbase.Billing.Plan.Bundle.Resolver.sync(sub.id)

      assert Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement.packages ==
               ["market", "social"]

      shrunk = stripe_snapshot(user, ["market"])

      with_mocks retrieve_mock(shrunk) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", shrunk.id))
      end

      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) == ["market"]

      entitlement = Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement
      assert entitlement.packages == ["market"]
      refute "social_volume_total" in entitlement.metric_access["accessible"]
    end

    test "leaves a row with no stripe_item_id alone", %{user: user, sub: sub} do
      # What `Lifecycle.add_item/3` writes before it calls Stripe.
      {:ok, claim} =
        Item.create(%{subscription_id: sub.id, sku: "development", type: :package, quantity: 1})

      assert claim.stripe_item_id == nil

      # Stripe has not heard of it yet.
      stripe_sub = stripe_snapshot(user, ["market"])

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      assert %Item{stripe_item_id: nil} = Repo.reload!(claim)

      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) |> Enum.sort() == [
               "development",
               "market"
             ]
    end

    test "writes the Stripe item id onto a claim once Stripe reports it", %{user: user, sub: sub} do
      {:ok, claim} =
        Item.create(%{subscription_id: sub.id, sku: "social", type: :package, quantity: 1})

      stripe_sub = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      assert Repo.reload!(claim).stripe_item_id == "si_price_social_month"
    end

    test "repairs a stripe_item_id Stripe has changed rather than deleting the row",
         %{user: user, sub: sub} do
      [market] = Item.by_subscription(sub.id)
      assert market.stripe_item_id == "si_price_market_month"

      stripe_sub =
        stripe_snapshot(user, ["market"],
          item_ids: %{"price_market_month" => "si_reissued_by_stripe"}
        )

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      assert [%Item{} = repaired] = Item.by_subscription(sub.id)
      assert repaired.id == market.id
      assert repaired.stripe_item_id == "si_reissued_by_stripe"
    end

    test "preserves remove_at on an item that is still in Stripe", %{user: user, sub: sub} do
      {:ok, leaving} =
        Item.create(%{
          subscription_id: sub.id,
          sku: "social",
          type: :package,
          stripe_item_id: "si_price_social_month",
          quantity: 1
        })

      remove_at = DateTime.utc_now() |> DateTime.add(10, :day) |> DateTime.truncate(:second)
      {:ok, leaving} = leaving |> Item.changeset(%{remove_at: remove_at}) |> Repo.update()

      # ItemExpiry has not run yet, so Stripe still bills and reports the item.
      stripe_sub = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      assert DateTime.compare(Repo.reload!(leaving).remove_at, remove_at) == :eq
    end

    test "skips an unknown price id without touching the rest", %{user: user, sub: sub} do
      stripe_sub =
        stripe_snapshot(user, ["market"], extra_price_ids: ["price_mystery_thing"])

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: true} =
                     process(event("customer.subscription.updated", stripe_sub.id))
          end)

        assert log =~ "not in the bundle catalog"
        assert log =~ "price_mystery_thing"
      end

      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) == ["market"]
      assert Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement.packages == ["market"]
    end

    test "the same event applied twice produces identical state", %{user: user, sub: sub} do
      grown = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(grown) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", grown.id, "evt_first"))

        first = item_state(sub.id)
        first_entitlement = Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement

        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", grown.id, "evt_second"))

        second = item_state(sub.id)
        second_entitlement = Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement

        # Same rows - same ids, so nothing was deleted and re-inserted - and the
        # same resolved entitlement.
        assert length(second) == 2
        assert first == second
        assert first_entitlement.packages == second_entitlement.packages
        assert first_entitlement.api_call_limits == second_entitlement.api_call_limits
        assert first_entitlement.metric_access == second_entitlement.metric_access
      end
    end

    test "rolls the whole reconciliation back when an item cannot be written",
         %{user: user, sub: sub} do
      # Another subscription already owns the Stripe item id the new item would
      # claim, which violates the unique index on it. That is a genuine anomaly,
      # not a race to tolerate, so nothing is written and the event stays visible.
      other = insert(:subscription_pro, user: insert(:user), stripe_id: "sub_other")

      {:ok, _} =
        Item.create(%{
          subscription_id: other.id,
          sku: "social",
          type: :package,
          stripe_item_id: "si_price_social_month",
          quantity: 1
        })

      grown = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(grown) do
        capture_log(fn ->
          assert %StripeEvent{is_processed: false} =
                   process(event("customer.subscription.updated", grown.id))
        end)
      end

      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) == ["market"]
    end

    test "does not populate an empty local item set", %{user: user, sub: sub} do
      # The window inside `Lifecycle.subscribe/2` between writing the subscription
      # row and writing its items.
      Repo.delete_all(from(i in Item, where: i.subscription_id == ^sub.id))

      stripe_sub = stripe_snapshot(user, ["market", "social"])

      with_mocks retrieve_mock(stripe_sub) do
        log =
          capture_log(fn ->
            assert %StripeEvent{is_processed: true} =
                     process(event("customer.subscription.updated", stripe_sub.id))
          end)

        assert log =~ "has no local items while Stripe reports 2"
      end

      assert Item.by_subscription(sub.id) == []
    end

    test "takes an add-on quantity from Stripe but pins a package to one",
         %{user: user, sub: sub} do
      make_sellable("api_calls_500k", "month")

      stripe_sub =
        stripe_snapshot(user, ["market", "api_calls_500k"],
          quantities: %{"price_market_month" => 3, "price_api_calls_500k_month" => 2}
        )

      with_mocks retrieve_mock(stripe_sub) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.updated", stripe_sub.id))
      end

      items = Map.new(Item.by_subscription(sub.id), &{&1.sku, &1})
      assert items["market"].quantity == 1
      assert items["api_calls_500k"].quantity == 2

      entitlement = Subscription.by_stripe_id(sub.stripe_id).bundle_entitlement
      assert entitlement.api_call_limits["month"] == 100_000 + 2 * 500_000
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # customer.subscription.deleted
  # ────────────────────────────────────────────────────────────────────────────

  describe "bundle customer.subscription.deleted" do
    test "cancels the subscription and drops the call quota", %{user: user} do
      stripe_sub = bundle_stripe_sub(customer: user.stripe_customer_id, skus: ["market"])
      sub = seed_bundle_subscription(user, stripe_sub, ["market"])
      {:ok, _} = Sanbase.Billing.Plan.Bundle.Resolver.sync(sub.id)

      acl = acl(user)
      assert acl.api_calls_limit_plan == "sanapi_bundle"
      assert acl.resolved_api_call_limits["month"] == 100_000

      canceled = %{stripe_sub | status: "canceled"}

      with_mocks retrieve_mock(canceled) do
        assert %StripeEvent{is_processed: true} =
                 process(event("customer.subscription.deleted", stripe_sub.id))
      end

      reloaded = Subscription.by_stripe_id(stripe_sub.id)
      assert reloaded.status == :canceled

      # Kept on purpose: access is blocked by the status, and support answers
      # "what did I pay for" from these.
      assert Enum.map(Item.by_subscription(sub.id), & &1.sku) == ["market"]
      assert reloaded.bundle_entitlement.packages == ["market"]

      dropped = acl(user)
      assert dropped.api_calls_limit_plan == "sanapi_free"
      assert dropped.resolved_api_call_limits == nil
    end
  end

  # ────────────────────────────────────────────────────────────────────────────
  # helpers
  # ────────────────────────────────────────────────────────────────────────────

  # The controller persists the event and then hands it to a task. Awaiting that
  # task is what makes the assertions deterministic.
  defp process(stripe_event) do
    {:ok, _} = StripeEvent.create(stripe_event)

    stripe_event
    |> StripeEvent.handle_event_async()
    |> Task.await(30_000)

    StripeEvent.by_id(stripe_event["id"])
  end

  defp event(type, subscription_id, event_id \\ nil) do
    %{
      "id" => event_id || "evt_" <> rand_hex_str(16),
      "type" => type,
      "data" => %{"object" => %{"id" => subscription_id}}
    }
  end

  defp retrieve_mock(stripe_sub) do
    [{StripeApi, [:passthrough], [retrieve_subscription: fn _id -> {:ok, stripe_sub} end]}]
  end

  # A legacy subscription as Stripe reports it: one item carrying a `plan`, whose
  # id is on the PRO plan row.
  defp legacy_stripe_sub(opts) do
    {:ok, stripe_sub} =
      StripeApiTestResponse.retrieve_subscription_resp(
        stripe_id: Keyword.get(opts, :stripe_id, "sub_legacy_" <> rand_hex_str(8)),
        status: Keyword.get(opts, :status, "active")
      )

    %{stripe_sub | customer: Keyword.fetch!(opts, :customer)}
  end

  # A bundle subscription as Stripe reports it: Price-based items, and an item id
  # that is a function of the price so that a code path losing ids cannot pass.
  defp bundle_stripe_sub(opts) do
    interval = Keyword.get(opts, :interval, "month")

    price_ids =
      Keyword.get_lazy(opts, :price_ids, fn ->
        Enum.map(Keyword.get(opts, :skus, []), &"price_#{&1}_#{interval}")
      end) ++ Keyword.get(opts, :extra_price_ids, [])

    {:ok, stripe_sub} =
      StripeApiTestResponse.retrieve_subscription_resp(
        stripe_id: Keyword.get(opts, :stripe_id, "sub_bundle_" <> rand_hex_str(8)),
        status: Keyword.get(opts, :status, "active"),
        price_ids: price_ids
      )

    item_ids = Keyword.get(opts, :item_ids, %{})
    quantities = Keyword.get(opts, :quantities, %{})

    data =
      Enum.map(stripe_sub.items.data, fn item ->
        %{
          item
          | id: Map.get(item_ids, item.price.id, "si_" <> item.price.id),
            quantity: Map.get(quantities, item.price.id, 1)
        }
      end)

    %{
      stripe_sub
      | customer: Keyword.fetch!(opts, :customer),
        items: %{stripe_sub.items | data: data}
    }
  end

  # Every Stripe snapshot in the reconciliation block has to describe the *same*
  # subscription, or the event would be about one we do not have.
  defp stripe_snapshot(user, skus, opts \\ []) do
    bundle_stripe_sub(
      [stripe_id: @reconciled_stripe_id, customer: user.stripe_customer_id, skus: skus] ++ opts
    )
  end

  # What `Lifecycle.subscribe/2` leaves behind, minus the entitlement, so a test
  # can tell whether the webhook resolved it.
  defp seed_bundle_subscription(user, stripe_sub, skus, interval \\ "month") do
    plan = Plan.bundle_plan(interval)

    sub =
      insert(:subscription_pro,
        user: user,
        plan_id: plan.id,
        stripe_id: stripe_sub.id,
        status: :active
      )

    for sku <- skus do
      {:ok, _} =
        Item.create(%{
          subscription_id: sub.id,
          sku: sku,
          type: :package,
          stripe_item_id: "si_price_#{sku}_#{interval}",
          quantity: 1
        })
    end

    Subscription.by_id(sub.id)
  end

  defp item_state(subscription_id) do
    subscription_id
    |> Item.by_subscription()
    |> Enum.map(&{&1.id, &1.sku, &1.type, &1.stripe_item_id, &1.quantity, &1.remove_at})
    |> Enum.sort()
  end

  defp acl(user), do: Repo.get_by!(ApiCallLimit, user_id: user.id)

  # `Catalog.ensure_local_catalog/0` seeds every SKU, add-ons with no amount. This
  # is what `Catalog.sync_with_stripe/0` would have written, without Stripe.
  defp make_sellable(sku, interval) do
    {1, _} =
      from(p in Price, where: p.sku == ^sku and p.interval == ^interval and p.is_active)
      |> Repo.update_all(set: [stripe_price_id: "price_#{sku}_#{interval}", amount: 35_000])

    :ok
  end

  defp insert_bundle_marker_plans(product_api_id) do
    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9603")

    for {interval, id} <- [{"month", 9601}, {"year", 9602}] do
      case Plan.bundle_plan(interval) do
        nil ->
          insert(:plan_pro,
            id: id,
            name: "BUNDLE",
            product_id: product_api_id,
            interval: interval,
            amount: 0,
            is_private: true,
            stripe_id: "plan_bundle_#{interval}_" <> Ecto.UUID.generate()
          )

        %Plan{} = plan ->
          plan
      end
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
            module: "Sanbase.Metric.BundleWebhookTestAdapter",
            metric: metric,
            category_id: category.id
          })
      end
    end
  end
end
