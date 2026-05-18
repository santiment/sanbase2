defmodule Sanbase.Billing.SubscriptionTest do
  use Sanbase.DataCase

  import Sanbase.Factory
  import Mock

  alias Sanbase.Billing.{Subscription, Plan.AccessChecker, Plan}
  alias Sanbase.StripeApiTestResponse
  alias Sanbase.StripeApi

  setup do
    %{user: insert(:user)}
  end

  describe "#maybe_validate_san_holder_coupon" do
    setup_with_mocks(
      [
        {StripeApi, [:passthrough],
         [create_product: fn _ -> StripeApiTestResponse.create_product_resp() end]},
        {StripeApi, [:passthrough],
         [create_plan: fn _ -> StripeApiTestResponse.create_plan_resp() end]},
        {StripeApi, [:passthrough],
         [
           create_customer_with_card: fn _, _ ->
             StripeApiTestResponse.create_or_update_customer_resp()
           end
         ]},
        {StripeApi, [:passthrough],
         [create_coupon: fn _ -> StripeApiTestResponse.create_coupon_resp() end]},
        {StripeApi, [:passthrough],
         [
           retrieve_coupon: fn coupon ->
             {:ok, %Stripe.Coupon{id: coupon, percent_off: 20}}
           end
         ]},
        {StripeApi, [:passthrough],
         [create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end]},
        {Sanbase.Messaging.Discord, [:passthrough], [send_notification: fn _, _, _ -> :ok end]},
        {Sanbase.TemplateMailer, [:passthrough],
         send: fn _, _, _ -> {:ok, %{"status" => "sent"}} end}
      ],
      context
    ) do
      {:ok, context}
    end

    test "SAN_HOLDER_1000 coupon with sufficient balance retrieves Stripe coupon", context do
      user = insert(:staked_user, email: "test@example.com")
      plan = context.plans.plan_pro_sanbase

      {:ok, subscription} = Subscription.subscribe(user, plan, "card_token", "SAN_HOLDER_1000")

      assert subscription.status == :active
      assert_called(StripeApi.retrieve_coupon("SAN_HOLDER_1000"))
    end

    test "SAN_HOLDER_1000 coupon with insufficient balance returns error", context do
      user = insert(:user, email: "test@example.com")
      plan = context.plans.plan_pro_sanbase

      result = Subscription.subscribe(user, plan, "card_token", "SAN_HOLDER_1000")

      assert {:error, "You need at least 1000 SAN tokens to use this discount code"} = result
      refute called(StripeApi.retrieve_coupon("SAN_HOLDER_1000"))
    end

    test "automatic discount (no coupon) with sufficient balance creates coupon", context do
      user = insert(:staked_user, email: "test@example.com")
      plan = context.plans.plan_pro_sanbase

      {:ok, subscription} = Subscription.subscribe(user, plan, "card_token", nil)

      assert subscription.status == :active
      assert_called(StripeApi.create_coupon(%{percent_off: 20, duration: "forever"}))
    end

    test "automatic discount (no coupon) with insufficient balance applies no discount",
         context do
      user = insert(:user, email: "test@example.com")
      plan = context.plans.plan_pro_sanbase

      {:ok, subscription} = Subscription.subscribe(user, plan, "card_token", nil)

      assert subscription.status == :active
      refute called(StripeApi.create_coupon(:_))
    end

    test "user with exactly 1000 SAN qualifies for SAN_HOLDER_1000 coupon", context do
      user = insert(:user, email: "test@example.com", san_balance: Decimal.new(1000))
      plan = context.plans.plan_pro_sanbase

      {:ok, subscription} = Subscription.subscribe(user, plan, "card_token", "SAN_HOLDER_1000")

      assert subscription.status == :active
      assert_called(StripeApi.retrieve_coupon("SAN_HOLDER_1000"))
    end

    test "user with 999 SAN does not qualify for SAN_HOLDER_1000 coupon", context do
      user = insert(:user, email: "test@example.com", san_balance: Decimal.new(999))
      plan = context.plans.plan_pro_sanbase

      result = Subscription.subscribe(user, plan, "card_token", "SAN_HOLDER_1000")

      assert {:error, "You need at least 1000 SAN tokens to use this discount code"} = result
    end

    test "other coupons pass through unchanged", context do
      user = insert(:user, email: "test@example.com")
      plan = context.plans.plan_pro_sanbase

      with_mocks([
        {StripeApi, [:passthrough],
         [
           create_customer_with_card: fn _, _ ->
             StripeApiTestResponse.create_or_update_customer_resp()
           end,
           retrieve_coupon: fn "OTHER_COUPON" -> {:ok, %Stripe.Coupon{id: "OTHER_COUPON"}} end,
           create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end
         ]}
      ]) do
        {:ok, subscription} = Subscription.subscribe(user, plan, "card_token", "OTHER_COUPON")

        assert subscription.status == :active
        assert_called(StripeApi.retrieve_coupon("OTHER_COUPON"))
      end
    end
  end

  describe "#update_subscription - SAN discount on upgrade" do
    test "applies SAN discount when user has 1000+ SAN and no existing coupon", context do
      user = insert(:user, email: "test@example.com", san_balance: Decimal.new(1000))
      subscription = insert(:subscription_pro_sanbase, user: user, stripe_id: "sub_test_upgrade")
      new_plan = context.plans.plan_pro_sanbase_yearly

      stripe_sub_no_discount =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: "sub_test_upgrade") |> elem(1)

      test_pid = self()

      with_mocks([
        {Stripe.Subscription, [],
         [
           retrieve: fn _stripe_id, _opts -> {:ok, stripe_sub_no_discount} end,
           update: fn _stripe_id, params, _opts ->
             send(test_pid, {:update_params, params})
             StripeApiTestResponse.update_subscription_resp()
           end
         ]}
      ]) do
        {:ok, _updated} = Subscription.update_subscription(subscription, new_plan)

        assert_receive {:update_params, params}
        assert params[:coupon] == "SAN_HOLDER_1000"
      end
    end

    test "does not apply coupon when subscription already has a discount", context do
      user = insert(:staked_user, email: "test@example.com")
      subscription = insert(:subscription_pro_sanbase, user: user, stripe_id: "sub_test_upgrade")
      new_plan = context.plans.plan_pro_sanbase_yearly

      stripe_sub_with_discount =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: "sub_test_upgrade")
        |> elem(1)
        |> Map.put(:discount, %{coupon: %{id: "existing_coupon", percent_off: 10}})

      test_pid = self()

      with_mocks([
        {Stripe.Subscription, [],
         [
           retrieve: fn _stripe_id, _opts -> {:ok, stripe_sub_with_discount} end,
           update: fn _stripe_id, params, _opts ->
             send(test_pid, {:update_params, params})
             StripeApiTestResponse.update_subscription_resp()
           end
         ]}
      ]) do
        {:ok, _updated} = Subscription.update_subscription(subscription, new_plan)

        assert_receive {:update_params, params}
        refute Map.has_key?(params, :coupon)
      end
    end

    test "does not apply coupon when user has less than 1000 SAN", context do
      user = insert(:user, email: "test@example.com", san_balance: Decimal.new(500))
      subscription = insert(:subscription_pro_sanbase, user: user, stripe_id: "sub_test_upgrade")
      new_plan = context.plans.plan_pro_sanbase_yearly

      stripe_sub_no_discount =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: "sub_test_upgrade") |> elem(1)

      test_pid = self()

      with_mocks([
        {Stripe.Subscription, [],
         [
           retrieve: fn _stripe_id, _opts -> {:ok, stripe_sub_no_discount} end,
           update: fn _stripe_id, params, _opts ->
             send(test_pid, {:update_params, params})
             StripeApiTestResponse.update_subscription_resp()
           end
         ]}
      ]) do
        {:ok, _updated} = Subscription.update_subscription(subscription, new_plan)

        assert_receive {:update_params, params}
        refute Map.has_key?(params, :coupon)
      end
    end

    test "upgrade works for user without SAN balance (no regression)", context do
      user = insert(:user, email: "test@example.com")
      subscription = insert(:subscription_pro_sanbase, user: user, stripe_id: "sub_test_upgrade")
      new_plan = context.plans.plan_pro_sanbase_yearly

      stripe_sub_no_discount =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: "sub_test_upgrade") |> elem(1)

      with_mocks([
        {Stripe.Subscription, [],
         [
           retrieve: fn _stripe_id, _opts -> {:ok, stripe_sub_no_discount} end,
           update: fn _stripe_id, _params, _opts ->
             StripeApiTestResponse.update_subscription_resp()
           end
         ]}
      ]) do
        result = Subscription.update_subscription(subscription, new_plan)
        assert {:ok, _updated} = result
      end
    end
  end

  describe "#sync_subscription_with_stripe" do
    setup(context) do
      stripe_base_subscription =
        StripeApiTestResponse.create_subscription_resp(stripe_id: "test stripe id") |> elem(1)

      stripe_subscription =
        stripe_base_subscription
        |> Map.merge(%{
          status: "trialing",
          trial_end: Timex.now() |> DateTime.to_unix()
        })

      {:ok,
       stripe_subscription: stripe_subscription,
       db_subscription:
         insert(:subscription_pro_sanbase, user: context.user, stripe_id: "test stripe id")}
    end

    test "copy fields from existing Stripe subscription", context do
      Subscription.sync_subscription_with_stripe(
        context.stripe_subscription,
        context.db_subscription
      )

      subscription = Subscription.by_id(context.db_subscription.id)
      assert subscription.status == :trialing

      assert subscription.trial_end ==
               context.stripe_subscription.trial_end |> DateTime.from_unix!()

      stripe_plan_id = (context.stripe_subscription.items.data |> hd()).plan.id
      assert subscription.plan_id == Plan.by_stripe_id(stripe_plan_id).id
      assert subscription.cancel_at_period_end == context.stripe_subscription.cancel_at_period_end

      assert subscription.current_period_end ==
               context.stripe_subscription.current_period_end |> DateTime.from_unix!()
    end

    test "retrieve Stripe subscription and copy fields", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [retrieve_subscription: fn _ -> {:ok, context.stripe_subscription} end]}
      ]) do
        Subscription.sync_subscription_with_stripe(context.db_subscription)
        subscription = Subscription.by_id(context.db_subscription.id)
        assert subscription.status == :trialing

        assert subscription.trial_end ==
                 context.stripe_subscription.trial_end |> DateTime.from_unix!()

        stripe_plan_id = (context.stripe_subscription.items.data |> hd()).plan.id
        assert subscription.plan_id == Plan.by_stripe_id(stripe_plan_id).id

        assert subscription.cancel_at_period_end ==
                 context.stripe_subscription.cancel_at_period_end

        assert subscription.current_period_end ==
                 context.stripe_subscription.current_period_end |> DateTime.from_unix!()
      end
    end

    test "when there is no stripe_id, do nothing", context do
      db_subscription = context.db_subscription |> Map.put(:stripe_id, nil)
      assert Subscription.sync_subscription_with_stripe(db_subscription) == :ok
    end
  end

  describe "#restricted?" do
    test "network_growth and daily_active_deposits are restricted" do
      assert AccessChecker.restricted?({:query, :network_growth})
      assert AccessChecker.restricted?({:query, :daily_active_deposits})
    end

    test "all_projects and history_price are not restricted" do
      refute AccessChecker.restricted?({:query, :all_projects})
      refute AccessChecker.restricted?({:query, :history_price})
    end
  end

  describe "#user_subscriptions" do
    test "when there are subscriptions - currentUser return list of subscriptions", context do
      insert(:subscription_essential, user: context.user)

      subscription = Subscription.user_subscriptions(context.user) |> hd()
      assert subscription.plan.name == "ESSENTIAL"
    end

    test "when there are no subscriptions - return []", context do
      assert Subscription.user_subscriptions(context.user) == []
    end

    test "only active subscriptions", context do
      insert(:subscription_essential,
        user: context.user,
        cancel_at_period_end: true,
        status: "canceled"
      )

      assert Subscription.user_subscriptions(context.user) == []
    end
  end

  describe "#current_subscription" do
    test "when there is subscription - return it", context do
      insert(:subscription_essential, user: context.user)

      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription.plan.id == context.plans.plan_essential.id
    end

    test "when there isn't - return nil", context do
      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription == nil
    end

    test "only active subscriptions", context do
      insert(:subscription_essential,
        user: context.user,
        cancel_at_period_end: true,
        status: "canceled"
      )

      current_subscription =
        Subscription.current_subscription(context.user, context.product_api.id)

      assert current_subscription == nil
    end
  end
end
