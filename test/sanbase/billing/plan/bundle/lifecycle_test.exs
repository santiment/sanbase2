defmodule Sanbase.Billing.Plan.Bundle.LifecycleTest do
  use Sanbase.DataCase, async: false

  import Ecto.Query
  import Mock
  import Sanbase.Factory

  alias Sanbase.Accounts.Role
  alias Sanbase.Accounts.UserRole
  alias Sanbase.Billing.Plan
  alias Sanbase.Billing.Plan.Bundle.{Catalog, Lifecycle, Package, PackageSnapshot, Price}
  alias Sanbase.Billing.Subscription
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

    Repo.query!("ALTER SEQUENCE plans_id_seq RESTART WITH 9603")

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

  describe "subscribe" do
    setup %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
      :ok
    end

    test "creates items and entitlement for team in legacy mode", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert Plan.type(sub.plan.name) == :bundle
        assert sub.bundle_entitlement != nil

        items = Item.by_subscription(sub.id)
        assert Enum.map(items, & &1.sku) == ["market"]

        # The Stripe item id is stored as Stripe reported it, so the item can be
        # addressed later.
        assert Enum.map(items, & &1.stripe_item_id) == ["si_price_market_month"]
      end
    end

    test "auto-replaces BUSINESS_PRO after success", %{user: user} = context do
      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: context.plans.plan_business_pro_monthly.id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert Plan.type(sub.plan.name) == :bundle
        assert Repo.reload!(legacy).status == :canceled
        assert legacy.stripe_id in calls(:cancel_with_proration)
      end
    end

    test "keeps BUSINESS_PRO when the bundle's first charge is declined",
         %{user: user} = context do
      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: context.plans.plan_business_pro_monthly.id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      # A declined first invoice is not an error tuple. Stripe answers
      # `{:ok, subscription}` with status `incomplete`, which reaches the end of
      # `subscribe/2` looking exactly like a completed purchase - and cancelling
      # on that basis leaves the customer paying for neither plan while holding
      # a credit against a bundle that will never charge.
      with_mocks stripe_mocks(subscription_status: "incomplete") do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert sub.status == :incomplete
        assert Repo.reload!(legacy).status == :active
        assert calls(:cancel_with_proration) == []
      end
    end

    test "rejects a second bundle subscribe and leaves the first alone", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, first} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:error, "You already have an active SanAPI subscription on the new offering"} =
                 Lifecycle.subscribe(user, packages: ["social"], interval: "month")

        assert Repo.reload!(first).status == :active
        assert Enum.map(Item.by_subscription(first.id), & &1.sku) == ["market"]
      end
    end

    test "rejects CUSTOM auto-replace", %{user: user} = context do
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

      assert {:error, "Active bespoke (custom) SanAPI subscription cannot be auto-replaced"} =
               Lifecycle.subscribe(user, packages: ["market"], interval: "month")
    end

    test "rejects an unknown package before charging", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:error, message} =
                 Lifecycle.subscribe(user, packages: ["not_a_package"], interval: "month")

        assert message =~ "is not sellable"
        assert calls(:create_bundle_subscription) == []
      end
    end

    test "refuses to sell before a package snapshot is published", %{user: user} do
      Repo.delete_all(PackageSnapshot)

      with_mocks stripe_mocks() do
        assert {:error, message} =
                 Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert message =~ "has not been published yet"
        assert calls(:create_bundle_subscription) == []
      end
    end

    test "rejects an expired coupon before charging", %{user: user} do
      insert_promo_code(user, "OLDCODE", DateTime.add(DateTime.utc_now(), -10, :day))

      with_mocks stripe_mocks() do
        assert {:error, "The coupon has expired."} =
                 Lifecycle.subscribe(user,
                   packages: ["market"],
                   interval: "month",
                   coupon: "OLDCODE"
                 )

        assert calls(:create_bundle_subscription) == []
      end
    end

    test "reports a refused payment method instead of charging", %{user: user} do
      # A card Stripe refuses used to blow up as a MatchError inside
      # attach_payment_method_to_customer, so the caller got a crash instead of
      # something it could show the customer.
      declined = %Stripe.Error{
        source: :stripe,
        code: :card_declined,
        message: "Your card was declined."
      }

      with_mocks stripe_mocks(attach_payment_method_to_customer: {:error, declined}) do
        assert {:error, ^declined} =
                 Lifecycle.subscribe(user,
                   packages: ["market"],
                   interval: "month",
                   payment_method_id: "pm_declined"
                 )

        assert calls(:attach_payment_method_to_customer) == ["pm_declined"]
        assert calls(:create_bundle_subscription) == []
      end
    end

    test "attaches the given payment method before the subscription is charged", %{user: user} do
      # The subscription is created `off_session`, so the payment method has to be
      # attached and made the customer's default first or the first invoice has
      # nothing to charge.
      with_mocks stripe_mocks(attach_payment_method_to_customer: {:ok, user}) do
        assert {:ok, _sub} =
                 Lifecycle.subscribe(user,
                   packages: ["market"],
                   interval: "month",
                   payment_method_id: "pm_card_visa"
                 )

        assert calls(:attach_payment_method_to_customer) == ["pm_card_visa"]

        assert calls(:order) == [:attach_payment_method_to_customer, :create_bundle_subscription]

        assert [%{customer: "cus_" <> _}] = calls(:create_bundle_subscription)
      end
    end

    test "asks Stripe to create nothing at all if the first invoice cannot be paid",
         %{user: user} = context do
      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: context.plans.plan_business_pro_monthly.id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      declined =
        {:error, %Stripe.Error{source: :stripe, code: :card_declined, message: "declined"}}

      with_mocks stripe_mocks(create_bundle_subscription: declined) do
        assert ^declined = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        # Without `error_if_incomplete` this same decline comes back as
        # `{:ok, subscription}` with status `incomplete`, indistinguishable from a
        # sale, and Stripe keeps its open invoice around to retry.
        assert [%{payment_behavior: "error_if_incomplete"}] = calls(:create_bundle_subscription)

        # Nothing was bought: no bundle row was written, and the plan the customer
        # is still paying for is untouched.
        subscription_ids =
          from(s in Subscription, where: s.user_id == ^user.id, select: s.id) |> Repo.all()

        assert subscription_ids == [legacy.id]
        assert Repo.reload!(legacy).status == :active
        assert calls(:cancel_with_proration) == []
      end
    end

    test "cancels the Stripe subscription when the items cannot be stored", %{user: user} do
      # Sellable, but not a real package - so the price resolves, Stripe charges,
      # and only then does the item fail to validate.
      insert_unsellable_looking_price("bogus_package", "month")

      with_mocks stripe_mocks() do
        assert {:error, _reason} =
                 Lifecycle.subscribe(user, packages: ["bogus_package"], interval: "month")

        # Charged, then cancelled again rather than left charging for a
        # subscription that grants nothing.
        assert [stripe_id] = calls(:cancel_with_proration)
        assert %Subscription{status: :canceled} = Subscription.by_stripe_id(stripe_id)
      end
    end
  end

  describe "items" do
    setup %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
      :ok
    end

    test "add_item stores the Stripe item id it was given", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
        assert {:ok, sub} = Lifecycle.add_item(user, sub.id, "social")

        items = Item.by_subscription(sub.id)
        assert Enum.sort(Enum.map(items, & &1.sku)) == ["market", "social"]

        social = Enum.find(items, &(&1.sku == "social"))
        assert social.stripe_item_id == "si_price_social_month"
      end
    end

    test "add_item refuses a SKU that is already there, and does not call Stripe twice",
         %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
        assert {:ok, _} = Lifecycle.add_item(user, sub.id, "social")

        assert {:error, message} = Lifecycle.add_item(user, sub.id, "social")
        assert message =~ "already on this subscription"

        assert length(calls(:create_subscription_item)) == 1
      end
    end

    test "add_item leaves nothing behind when Stripe refuses", %{user: user} do
      with_mocks stripe_mocks(create_subscription_item: {:error, :card_declined}) do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:error, :card_declined} = Lifecycle.add_item(user, sub.id, "social")

        # The claim was rolled back, so the customer can try again.
        assert Enum.map(Item.by_subscription(sub.id), & &1.sku) == ["market"]
      end
    end

    test "remove_item schedules the removal and changes nothing yet", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
        assert {:ok, sub} = Lifecycle.add_item(user, sub.id, "social")

        assert {:ok, sub} = Lifecycle.remove_item(user, sub.id, "social")

        social = Enum.find(Item.by_subscription(sub.id), &(&1.sku == "social"))
        assert social.remove_at == DateTime.truncate(sub.current_period_end, :second)

        # Paid for, so still owned: the entitlement keeps the package and Stripe has
        # not been asked to drop the item yet.
        assert Enum.sort(sub.bundle_entitlement.packages) == ["market", "social"]
        assert calls(:delete_subscription_item) == []
      end
    end

    test "remove_item refuses the last package", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:error, message} = Lifecycle.remove_item(user, sub.id, "market")
        assert message =~ "Cannot remove the last package"
      end
    end

    test "remove_item refuses the second-to-last package once the other is going",
         %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.remove_item(user, sub.id, "social")

        assert {:error, message} = Lifecycle.remove_item(user, sub.id, "market")
        assert message =~ "Cannot remove the last package"
      end
    end

    test "remove_item refuses an item already scheduled for removal", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.remove_item(user, sub.id, "social")

        assert {:error, message} = Lifecycle.remove_item(user, sub.id, "social")
        assert message =~ "already scheduled for removal"
      end
    end
  end

  describe "switch_interval" do
    setup %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
      :ok
    end

    test "moves the plan and re-prices the items by id", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
        assert sub.plan.interval == "month"

        assert {:ok, switched} = Lifecycle.switch_interval(user, sub.id)
        assert switched.plan.interval == "year"

        assert [%{items: [item], proration_behavior: "create_prorations"}] =
                 calls(:update_subscription)

        assert item == %{id: "si_price_market_month", price: "price_market_year"}

        assert Enum.map(Item.by_subscription(sub.id), & &1.stripe_item_id) ==
                 ["si_price_market_year"]
      end
    end

    test "switching twice never asks Stripe to add items alongside the old ones",
         %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:ok, _} = Lifecycle.switch_interval(user, sub.id)
        assert {:ok, back} = Lifecycle.switch_interval(user, sub.id)

        assert back.plan.interval == "month"

        # Every item in every request carries an id. An entry without one is an
        # instruction to Stripe to add another item and bill for both.
        for %{items: items} <- calls(:update_subscription), item <- items do
          assert Map.has_key?(item, :id)
        end
      end
    end

    test "drops an item that was scheduled for removal", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.remove_item(user, sub.id, "social")
        assert {:ok, switched} = Lifecycle.switch_interval(user, sub.id)

        # Gone locally and gone from the entitlement, rather than carried onto the
        # new interval. The item that stayed keeps the id from the response that
        # re-priced it - the second of the two, the only one that names it on its
        # new price.
        items = Item.by_subscription(sub.id)
        assert Enum.map(items, & &1.sku) == ["market"]
        assert Enum.map(items, & &1.stripe_item_id) == ["si_price_market_year"]
        assert switched.bundle_entitlement.packages == ["market"]
      end
    end

    test "never credits an item that was scheduled for removal", %{user: user} do
      # Stripe applies one `proration_behavior` per request, so a deletion sent
      # together with the re-price was prorated with it and credited the unused time
      # of a package the customer had paid for and kept - a near-full refund for a
      # period they had used, and one that survived switching back.
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.remove_item(user, sub.id, "social")
        assert {:ok, _} = Lifecycle.switch_interval(user, sub.id)

        # In this order: the deletion first, so that a re-price failing after it
        # leaves fewer items rather than a credit for items that are still billed.
        assert [drop, reprice] = calls(:update_subscription)

        assert drop == %{
                 items: [%{id: "si_price_social_month", deleted: true}],
                 proration_behavior: "none"
               }

        assert reprice == %{
                 items: [%{id: "si_price_market_month", price: "price_market_year"}],
                 proration_behavior: "create_prorations"
               }
      end
    end

    test "switches anyway when the item to drop is already gone from Stripe", %{user: user} do
      # Deletions go out before the re-price, so a re-price that fails leaves local
      # rows naming items Stripe no longer has. If this call refused to tolerate
      # that, every later attempt would die on the deletion and the subscription
      # would be stuck on the wrong interval until `remove_at` came around - a month
      # away, a year on the annual interval.
      missing = %Stripe.Error{source: :stripe, code: :resource_missing, message: "No such item"}

      with_mocks stripe_mocks(drop_items: {:error, missing}) do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.remove_item(user, sub.id, "social")
        assert {:ok, switched} = Lifecycle.switch_interval(user, sub.id)

        assert switched.plan.interval == "year"
        assert switched.bundle_entitlement.packages == ["market"]

        # It still asked, and it still asked first.
        assert [%{proration_behavior: "none"}, %{proration_behavior: "create_prorations"}] =
                 calls(:update_subscription)
      end
    end

    test "asks Stripe once when nothing is scheduled for removal", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} =
                 Lifecycle.subscribe(user, packages: ["market", "social"], interval: "month")

        assert {:ok, _} = Lifecycle.switch_interval(user, sub.id)

        # Nothing to delete, so no request with an empty `items` array in front of
        # the re-price.
        assert [reprice] = calls(:update_subscription)

        assert reprice == %{
                 items: [
                   %{id: "si_price_market_month", price: "price_market_year"},
                   %{id: "si_price_social_month", price: "price_social_year"}
                 ],
                 proration_behavior: "create_prorations"
               }
      end
    end
  end

  describe "cancel" do
    setup %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
      :ok
    end

    test "schedules cancellation at period end", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:ok, %{is_scheduled_for_cancellation: true}} = Lifecycle.cancel(user, sub.id)
        assert sub.stripe_id in calls(:cancel_at_period_end)
      end
    end

    test "works even after the offering is withdrawn from sale", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        # Not a team member any more and the plans are private: buying is closed,
        # cancelling must not be.
        Repo.delete_all(UserRole)

        assert {:ok, %{is_scheduled_for_cancellation: true}} = Lifecycle.cancel(user, sub.id)
      end
    end

    test "a cancelling subscription refuses further changes", %{user: user} do
      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
        assert {:ok, _} = Lifecycle.cancel(user, sub.id)

        assert {:error, message} = Lifecycle.add_item(user, sub.id, "social")
        assert message =~ "already scheduled for cancellation"
      end
    end
  end

  describe "ownership" do
    test "another user cannot touch the subscription", %{user: user} do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())
      other = insert(:user)
      {:ok, _} = UserRole.create(other.id, Role.san_team_role_id())

      with_mocks stripe_mocks() do
        assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

        assert {:error, "Subscription does not belong to the user"} =
                 Lifecycle.add_item(other, sub.id, "social")

        assert {:error, "Subscription does not belong to the user"} =
                 Lifecycle.cancel(other, sub.id)
      end
    end

    test "a non-bundle subscription is refused", %{user: user} = context do
      {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

      legacy =
        insert(:subscription_pro,
          user_id: user.id,
          plan_id: context.plans.plan_business_pro_monthly.id,
          status: :active,
          stripe_id: "sub_legacy_" <> Ecto.UUID.generate()
        )

      assert {:error, "Subscription is not a bundle"} =
               Lifecycle.add_item(user, legacy.id, "social")

      assert {:error, "Subscription is not a bundle"} = Lifecycle.cancel(user, legacy.id)
    end
  end

  test "upgrade_downgrade rejects bundle subscriptions", %{user: user} = context do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks() do
      assert {:ok, sub} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")

      assert {:error, msg} =
               StripeApi.upgrade_downgrade(sub, context.plans.plan_business_max_monthly)

      assert msg =~ "Bundle subscriptions cannot use upgrade/downgrade"
    end
  end

  test "cancel_stale_replaced_subscriptions cancels a legacy sub left behind",
       %{user: user} = context do
    {:ok, _} = UserRole.create(user.id, Role.san_team_role_id())

    with_mocks stripe_mocks() do
      assert {:ok, _} = Lifecycle.subscribe(user, packages: ["market"], interval: "month")
    end

    # Added after the purchase, the way a failed cancel leaves it behind.
    legacy =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: context.plans.plan_business_pro_monthly.id,
        status: :active,
        stripe_id: "sub_leftover_" <> Ecto.UUID.generate()
      )

    with_mocks stripe_mocks() do
      assert %{canceled: 1, failed: 0} = Lifecycle.cancel_stale_replaced_subscriptions()
      assert Repo.reload!(legacy).status == :canceled
    end
  end

  test "cancel_stale_replaced_subscriptions ignores a bundle whose first charge was declined",
       %{user: user} = context do
    bundle_plan = Plan.bundle_plan("month")

    # Bought, so it has a Stripe id - but the charge was refused, so it grants
    # nothing and replaces nothing. The retry must reach the same conclusion the
    # inline cancel in `subscribe/2` did, or the two undo each other.
    insert(:subscription_pro,
      user_id: user.id,
      plan_id: bundle_plan.id,
      status: :incomplete,
      stripe_id: "sub_declined_" <> Ecto.UUID.generate()
    )

    legacy =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: context.plans.plan_business_pro_monthly.id,
        status: :active,
        stripe_id: "sub_real_" <> Ecto.UUID.generate()
      )

    with_mocks stripe_mocks() do
      assert %{canceled: 0, failed: 0} = Lifecycle.cancel_stale_replaced_subscriptions()

      assert Repo.reload!(legacy).status == :active
      assert calls(:cancel_with_proration) == []
    end
  end

  test "cancel_stale_replaced_subscriptions ignores a bundle created by hand in the admin panel",
       %{user: user} = context do
    bundle_plan = Plan.bundle_plan("month")

    # No stripe_id: exactly what /admin/bundle_subscriptions inserts. Nothing was
    # bought, so nothing is being replaced.
    insert(:subscription_pro,
      user_id: user.id,
      plan_id: bundle_plan.id,
      status: :active,
      stripe_id: nil
    )

    legacy =
      insert(:subscription_pro,
        user_id: user.id,
        plan_id: context.plans.plan_business_pro_monthly.id,
        status: :active,
        stripe_id: "sub_real_" <> Ecto.UUID.generate()
      )

    with_mocks stripe_mocks() do
      assert %{canceled: 0, failed: 0} = Lifecycle.cancel_stale_replaced_subscriptions()

      # The customer's real, paid subscription is untouched.
      assert Repo.reload!(legacy).status == :active
      assert calls(:cancel_with_proration) == []
    end
  end

  # --- helpers ---

  # Every mocked call is recorded so a test can assert what Stripe was actually
  # asked to do. A mock that ignores its arguments cannot fail when the wrong
  # request is sent, which is the whole class of bug worth testing here.
  defp stripe_mocks(opts \\ []) do
    item_result = Keyword.get(opts, :create_subscription_item)
    attach_result = Keyword.get(opts, :attach_payment_method_to_customer)
    drop_items_result = Keyword.get(opts, :drop_items)
    subscription_status = Keyword.get(opts, :subscription_status, "active")
    create_sub_result = Keyword.get(opts, :create_bundle_subscription)

    [
      {StripeApi, [:passthrough],
       [
         attach_payment_method_to_customer: fn user, payment_method_id ->
           record(:attach_payment_method_to_customer, payment_method_id)
           record(:order, :attach_payment_method_to_customer)

           attach_result || :meck.passthrough([user, payment_method_id])
         end,
         create_bundle_subscription: fn params ->
           record(:create_bundle_subscription, params)
           record(:order, :create_bundle_subscription)
           price_ids = Enum.map(params.items, & &1.price)
           stripe_id = "sub_test_" <> Integer.to_string(System.unique_integer([:positive]))
           remember_prices(stripe_id, price_ids)

           create_sub_result ||
             with_stable_item_ids(
               StripeApiTestResponse.create_bundle_subscription_resp(
                 stripe_id: stripe_id,
                 price_ids: price_ids,
                 status: subscription_status
               )
             )
         end,
         create_subscription_item: fn subscription_id, price_id, _opts ->
           record(:create_subscription_item, {subscription_id, price_id})

           item_result ||
             StripeApiTestResponse.create_subscription_item_resp(
               id: "si_" <> price_id,
               price_id: price_id,
               subscription: subscription_id
             )
         end,
         update_subscription: fn stripe_id, params ->
           record(:update_subscription, params)

           if drop_items_result && deletion_request?(params) do
             drop_items_result
           else
             mocked_update_subscription(stripe_id, params)
           end
         end,
         delete_subscription_item: fn stripe_item_id, opts ->
           record(:delete_subscription_item, {stripe_item_id, opts})
           {:ok, %{id: stripe_item_id, deleted: true}}
         end,
         cancel_subscription_with_proration: fn stripe_id ->
           record(:cancel_with_proration, stripe_id)

           StripeApiTestResponse.cancel_subscription_with_proration_resp(
             stripe_id: stripe_id,
             price_ids: remembered_prices(stripe_id)
           )
         end,
         cancel_subscription_at_period_end: fn stripe_id ->
           record(:cancel_at_period_end, stripe_id)

           # Stripe answers with the subscription carrying the flag it was just
           # asked to set; a response without it would let the local row disagree.
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

  # Stripe keeps an item's id when its price changes. The canned response invents a
  # random one per call, which would hide a code path that loses ids, so they are
  # made a function of the price instead.
  defp with_stable_item_ids({:ok, %Stripe.Subscription{items: %Stripe.List{} = list} = sub}) do
    data = Enum.map(list.data, fn item -> %{item | id: "si_" <> item.price.id} end)

    {:ok, %{sub | items: %{list | data: data}}}
  end

  # Stripe answers an update with the subscription as it now stands, not with the
  # items the request named: one that only deletes items still comes back carrying
  # the ones that stayed, on the prices they already had. An interval switch reads
  # item ids out of one of its two responses, and a mock that answered a deletion
  # with nothing at all would not care which one.
  defp mocked_update_subscription(stripe_id, params) do
    price_ids = prices_after_update(stripe_id, Map.get(params, :items))
    remember_prices(stripe_id, price_ids)

    StripeApiTestResponse.update_subscription_resp(
      stripe_id: stripe_id,
      price_ids: price_ids
    )
    |> with_stable_item_ids()
  end

  defp deletion_request?(%{items: items}) when is_list(items) do
    Enum.any?(items, &Map.get(&1, :deleted, false))
  end

  defp deletion_request?(_params), do: false

  defp prices_after_update(stripe_id, nil), do: remembered_prices(stripe_id)

  defp prices_after_update(stripe_id, items) do
    {deleted, repriced} = Enum.split_with(items, &Map.get(&1, :deleted, false))

    case Enum.map(repriced, & &1.price) do
      [] -> remembered_prices(stripe_id) -- Enum.map(deleted, &deleted_item_price/1)
      price_ids -> price_ids
    end
  end

  # The inverse of `with_stable_item_ids/1`: an item id names the price it holds, so
  # a deletion by id says which price left.
  defp deleted_item_price(%{id: "si_" <> price_id}), do: price_id

  defp record(key, value) do
    Process.put({:stripe_calls, key}, [value | Process.get({:stripe_calls, key}, [])])
  end

  # A bundle subscription's items are Price-based, so every response about one has
  # to report prices rather than a legacy `plan` object. Remembering what a
  # subscription was last given keeps that true for the calls that carry no items
  # of their own, like cancelling.
  defp remember_prices(stripe_id, price_ids) do
    Process.put({:stripe_prices, stripe_id}, price_ids)
  end

  defp remembered_prices(stripe_id), do: Process.get({:stripe_prices, stripe_id}, [])

  defp calls(key), do: Process.get({:stripe_calls, key}, []) |> Enum.reverse()

  defp insert_promo_code(user, coupon, redeem_by) do
    {:ok, promo} =
      %Sanbase.Billing.UserPromoCode{}
      |> Sanbase.Billing.UserPromoCode.changeset(%{
        campaign: "lifecycle test",
        coupon: coupon,
        user_id: user.id,
        percent_off: 20,
        redeem_by: DateTime.truncate(redeem_by, :second)
      })
      |> Repo.insert()

    promo
  end

  defp insert_unsellable_looking_price(sku, interval) do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    Repo.insert_all("bundle_prices", [
      %{
        sku: sku,
        type: "package",
        interval: interval,
        stripe_price_id: "price_#{sku}_#{interval}",
        amount: 35_000,
        currency: "USD",
        is_active: true,
        inserted_at: now,
        updated_at: now
      }
    ])
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
