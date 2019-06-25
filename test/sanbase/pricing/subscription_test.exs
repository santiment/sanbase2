defmodule Sanbase.Pricing.SubscriptionTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Pricing.Subscription
  alias Sanbase.Auth.Apikey
  alias Sanbase.StripeApi
  alias Sanbase.Repo
  alias Sanbase.StripeApiTestReponse

  setup do
    free_user = insert(:user)
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    product = insert(:product)
    plan_essential = insert(:plan_essential, product: product)
    plan_pro = insert(:plan_pro, product: product)
    insert(:plan_premium, product: product)

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    {:ok, apikey_free} = Apikey.generate_apikey(free_user)
    conn_apikey_free = setup_apikey_auth(build_conn(), apikey_free)

    {:ok,
     conn: conn,
     user: user,
     product: product,
     plan_essential: plan_essential,
     plan_pro: plan_pro,
     conn_apikey: conn_apikey,
     conn_apikey_free: conn_apikey_free}
  end

  describe "#is_restricted?" do
    test "network_growth and mvrv_ratio are restricted" do
      assert Subscription.is_restricted?("network_growth")
      assert Subscription.is_restricted?("mvrv_ratio")
    end

    test "all_projects and history_price are not restricted" do
      refute Subscription.is_restricted?("all_projects")
      refute Subscription.is_restricted?("history_price")
    end
  end

  describe "#needs_advanced_plan?" do
    test "mvrv_ratio needs advanced plan subscription" do
      assert Subscription.needs_advanced_plan?("mvrv_ratio")
    end

    test "network_growth, all_projects and history_price does not need advanced plan subscription" do
      refute Subscription.needs_advanced_plan?("network_growth")
      refute Subscription.needs_advanced_plan?("all_projects")
      refute Subscription.needs_advanced_plan?("history_price")
    end
  end

  describe "#has_access?" do
    test "subscription to ESSENTIAL plan has access to STANDART metrics", context do
      subscription = insert(:subscription_essential, user: context.user) |> Repo.preload(:plan)

      assert Subscription.has_access?(subscription, "network_growth")
    end

    test "subscription to ESSENTIAL plan does not have access to ADVANCED metrics", context do
      subscription = insert(:subscription_essential, user: context.user) |> Repo.preload(:plan)

      refute Subscription.has_access?(subscription, "mvrv_ratio")
    end

    test "subscription to ESSENTIAL plan has access to not restricted metrics", context do
      subscription = insert(:subscription_essential, user: context.user) |> Repo.preload(:plan)

      assert Subscription.has_access?(subscription, "history_price")
    end

    test "subscription to PRO plan have access to both STANDART and ADVANCED metrics", context do
      subscription = insert(:subscription_pro, user: context.user) |> Repo.preload(:plan)

      assert Subscription.has_access?(subscription, "network_growth")
      assert Subscription.has_access?(subscription, "mvrv_ratio")
    end

    test "subscription to PRO plan has access to not restricted metrics", context do
      subscription = insert(:subscription_pro, user: context.user) |> Repo.preload(:plan)

      assert Subscription.has_access?(subscription, "history_price")
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
  end

  describe "#current_subscription" do
    test "when there is subscription - return it", context do
      insert(:subscription_essential, user: context.user)

      current_subscription = Subscription.current_subscription(context.user, context.product.id)
      assert current_subscription.plan.id == context.plan_essential.id
    end

    test "when there isn't - return nil", context do
      current_subscription = Subscription.current_subscription(context.user, context.product.id)
      assert current_subscription == nil
    end
  end

  describe "#subscribe" do
    test "successfull subscription", context do
      with_mocks([
        {StripeApi, [],
         [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
        {StripeApi, [], [create_coupon: fn _ -> StripeApiTestReponse.create_coupon_resp() end]},
        {StripeApi, [],
         [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]}
      ]) do
        {:ok,
         %Subscription{
           user_id: user_id,
           plan_id: plan_id,
           stripe_id: stripe_id
         }} =
          Subscription.subscribe(context.user.id, "test_card_token", context.plan_essential.id)

        assert user_id == context.user.id
        assert plan_id == context.plan_essential.id
        assert stripe_id != nil
      end
    end

    test "when user with provided id doesn't exist - logs the error and returns it", context do
      assert capture_log(fn ->
               {:error, reason} =
                 Subscription.subscribe(-1, "test_card_token", context.plan_essential.id)

               assert reason =~ "Cannot find user with id -1"
             end) =~ "Cannot find user with id -1"
    end

    test "when plan with provided id doesn't exist - logs the error and returns it", context do
      assert capture_log(fn ->
               {:error, reason} = Subscription.subscribe(context.user.id, "test_card_token", -1)

               assert reason =~ "Cannot find plan with id -1"
             end) =~ "Cannot find plan with id -1"
    end

    test "when creating customer in Stripe fails - logs the error and returns generic error",
         context do
      with_mock StripeApi, [],
        create_customer: fn _, _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        assert capture_log(fn ->
                 {:error, reason} =
                   Subscription.subscribe(
                     context.user.id,
                     "test_card_token",
                     context.plan_essential.id
                   )

                 assert reason == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end

    test "when creating coupon in Stripe fails - logs the error and returns generic error",
         context do
      with_mocks([
        {StripeApi, [],
         [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
        {StripeApi, [],
         [
           create_coupon: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        assert capture_log(fn ->
                 {:error, reason} =
                   Subscription.subscribe(
                     context.user.id,
                     "test_card_token",
                     context.plan_essential.id
                   )

                 assert reason == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end

    test "when creating subscription in Stripe fails - logs the error and returns generic error",
         context do
      with_mocks([
        {StripeApi, [],
         [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
        {StripeApi, [], [create_coupon: fn _ -> StripeApiTestReponse.create_coupon_resp() end]},
        {StripeApi, [],
         [
           create_subscription: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        assert capture_log(fn ->
                 {:error, reason} =
                   Subscription.subscribe(
                     context.user.id,
                     "test_card_token",
                     context.plan_essential.id
                   )

                 assert reason == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end
  end

  describe "#update_subscription" do
    test "successfully upgrade a subscription from ESSENTIAL to PRO", context do
      with_mocks([
        {Sanbase.StripeApi, [], [get_subscription_first_item_id: fn _ -> {:ok, "item_id"} end]},
        {Sanbase.StripeApi, [],
         [
           update_subscription: fn _, _ ->
             StripeApiTestReponse.update_subscription_resp()
           end
         ]}
      ]) do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")

        {:ok, update_result} =
          Subscription.update_subscription(subscription.id, context.plan_pro.id)

        assert update_result.plan.name == "PRO"
      end
    end

    test "successfully downgrade a subscription from PRO to ESSENTIAL", context do
      with_mocks([
        {Sanbase.StripeApi, [], [get_subscription_first_item_id: fn _ -> {:ok, "item_id"} end]},
        {Sanbase.StripeApi, [],
         [
           update_subscription: fn _, _ ->
             StripeApiTestReponse.update_subscription_resp()
           end
         ]}
      ]) do
        subscription = insert(:subscription_pro, user: context.user, stripe_id: "stripe_id")

        {:ok, update_result} =
          Subscription.update_subscription(subscription.id, context.plan_essential.id)

        assert update_result.plan.name == "ESSENTIAL"
      end
    end

    test "returns error when referred subscription doesn not exist", context do
      assert capture_log(fn ->
               {:error, reason} = Subscription.update_subscription(-1, context.plan_essential.id)

               assert reason == "Cannot find subscription with id -1"
             end) =~ "Upgrade/Downgrade failed - reason: Cannot find subscription with id -1"
    end

    test "returns error when referred plan doesn not exist", context do
      subscription = insert(:subscription_pro, user: context.user, stripe_id: "stripe_id")

      assert capture_log(fn ->
               {:error, reason} = Subscription.update_subscription(subscription.id, -1)

               assert reason == "Cannot find plan with id -1"
             end) =~ "Upgrade/Downgrade failed - reason: Cannot find plan with id -1"
    end
  end

  describe "#cancel_subscription" do
    test "successfully cancel a subscription", context do
      with_mocks([
        {Sanbase.StripeApi, [],
         [
           cancel_subscription: fn _ ->
             StripeApiTestReponse.update_subscription_resp()
           end
         ]}
      ]) do
        tomorrow = Timex.shift(Timex.now(), days: 1)

        subscription =
          insert(:subscription_essential,
            user: context.user,
            stripe_id: "stripe_id",
            current_period_end: tomorrow
          )

        {:ok, cancel_result} = Subscription.cancel_subscription(subscription.id)

        assert cancel_result == %{
                 scheduled_for_cancellation: true,
                 scheduled_for_cancellation_at: tomorrow
               }
      end
    end

    test "returns error when referred subscription doesn not exist", context do
      assert capture_log(fn ->
               {:error, reason} = Subscription.cancel_subscription(-1)

               assert reason == "Cannot find subscription with id -1"
             end) =~ "Canceling subscription failed - reason: Cannot find subscription with id -1"
    end
  end
end
