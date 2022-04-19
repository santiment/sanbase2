defmodule SanbaseWeb.Graphql.Billing.SubscribeApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Accounts.User
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestResponse

  @coupon_code "test_coupon"

  setup_with_mocks([
    {StripeApi, [:passthrough],
     [create_product: fn _ -> StripeApiTestResponse.create_product_resp() end]},
    {StripeApi, [:passthrough],
     [create_plan: fn _ -> StripeApiTestResponse.create_plan_resp() end]},
    {StripeApi, [:passthrough],
     [create_customer: fn _, _ -> StripeApiTestResponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [update_customer: fn _, _ -> StripeApiTestResponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [create_coupon: fn _ -> StripeApiTestResponse.create_coupon_resp() end]},
    {StripeApi, [:passthrough],
     [create_subscription: fn _ -> StripeApiTestResponse.create_subscription_resp() end]},
    {StripeApi, [:passthrough],
     [retrieve_coupon: fn _ -> {:ok, %Stripe.Coupon{id: @coupon_code}} end]},
    {StripeApi, [:passthrough], [delete_default_card: fn _ -> :ok end]},
    {Sanbase.StripeApi, [:passthrough],
     [
       update_subscription_item_by_id: fn _, _ ->
         StripeApiTestResponse.update_subscription_resp()
       end
     ]},
    {Sanbase.StripeApi, [:passthrough],
     [
       update_subscription: fn _, _ ->
         StripeApiTestResponse.update_subscription_resp()
       end
     ]},
    {Sanbase.StripeApi, [:passthrough],
     [
       cancel_subscription: fn _ ->
         StripeApiTestResponse.update_subscription_resp()
       end
     ]},
    {Sanbase.Notifications.Discord, [:passthrough],
     [
       send_notification: fn _, _, _ -> :ok end
     ]},
    {Sanbase.MandrillApi, [:passthrough], send: fn _, _, _, _ -> {:ok, %{"status" => "sent"}} end}
  ]) do
    # Needs to be staked to apply the discount
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "check coupon", context do
    with_mock StripeApi, [:passthrough],
      retrieve_coupon: fn _ ->
        {:ok,
         %Stripe.Coupon{
           id: @coupon_code,
           name: "alabala",
           valid: true,
           percent_off: 50,
           amount_off: nil
         }}
      end do
      query = check_coupon(@coupon_code)

      coupon = execute_query(context.conn, query, "getCoupon")

      assert coupon["percentOff"] == 50
      assert coupon["isValid"]
    end
  end

  test "update customer card", context do
    query = update_customer_card()
    response = execute_mutation(context.conn, query)

    assert response
  end

  test "delete customer card", context do
    query = delete_customer_card()
    response = execute_mutation(context.conn, query, "deleteDefaultPaymentInstrument")

    assert response
  end

  test "list products with plans", context do
    query = products_with_plans_query()

    result =
      context.conn
      |> execute_query(query, "productsWithPlans")
      |> hd()

    assert result["name"] == "Neuro by Santiment"
    assert length(result["plans"]) == 9
  end

  describe "#currentUser[subscriptions]" do
    test "when there are subscriptions - currentUser return list of subscriptions", context do
      insert(:subscription_essential, user: context.user)

      current_user = execute_query(context.conn, current_user_query(), "currentUser")
      subscription = current_user["subscriptions"] |> hd()

      assert subscription["plan"]["name"] == "ESSENTIAL"
    end

    test "when there are no subscriptions - return []", context do
      current_user = execute_query(context.conn, current_user_query(), "currentUser")
      assert current_user["subscriptions"] == []
    end

    test "when there are no active subscriptions - return []", context do
      insert(:subscription_essential,
        user: context.user,
        status: "canceled"
      )

      current_user = execute_query(context.conn, current_user_query(), "currentUser")
      assert current_user["subscriptions"] == []
    end
  end

  describe "subscribe mutation" do
    test "successful subscribe returns subscription", context do
      query = subscribe_mutation(context.plans.plan_essential.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert response["status"] == "ACTIVE"
      assert response["plan"]["name"] == context.plans.plan_essential.name
    end

    test "successful subscribe when user has stripe_customer_id", context do
      context.user |> User.changeset(%{stripe_customer_id: "alabala"}) |> Sanbase.Repo.update!()

      query = subscribe_mutation(context.plans.plan_essential.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert response["plan"]["name"] == context.plans.plan_essential.name
    end

    test "when not existing plan provided - returns proper error", context do
      query = subscribe_mutation(-1)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~ "Cannot find plan with id -1"
             end) =~ "Cannot find plan with id -1"
    end

    test "when creating customer in Stripe fails - logs the error and returns generic error",
         context do
      with_mock StripeApi, [:passthrough],
        create_customer: fn _, _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        query = subscribe_mutation(context.plans.plan_essential.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end

    test "when creating coupon fails - logs the error and returns generic error", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [create_customer: fn _, _ -> StripeApiTestResponse.create_or_update_customer_resp() end]},
        {StripeApi, [:passthrough],
         [
           create_coupon: fn _ ->
             {:error, %Stripe.Error{message: "invalid coupon", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        query = subscribe_mutation(context.plans.plan_essential.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "invalid coupon"
               end) =~ "invalid coupon"
      end
    end

    test "when creating subscription in Stripe fails - logs the error and returns generic error",
         context do
      with_mocks([
        {StripeApi, [:passthrough],
         [create_customer: fn _, _ -> StripeApiTestResponse.create_or_update_customer_resp() end]},
        {StripeApi, [:passthrough],
         [create_coupon: fn _ -> StripeApiTestResponse.create_coupon_resp() end]},
        {StripeApi, [:passthrough],
         [
           create_subscription: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        query = subscribe_mutation(context.plans.plan_essential.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end

    test "subscribe with coupon works", context do
      query = subscribe_with_coupon_mutation(context.plans.plan_essential.id, @coupon_code)
      response = execute_mutation(context.conn, query, "subscribe")

      assert_called(StripeApi.retrieve_coupon(@coupon_code))
      assert response["status"] == "ACTIVE"
      assert response["plan"]["name"] == context.plans.plan_essential.name
    end

    test "subscribe to Sanbase PRO plan gives 14 days free trial", context do
      query = subscribe_mutation(context.plans.plan_pro_sanbase.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert_called(StripeApi.create_subscription(%{trial_end: :_}))
      assert response["plan"]["name"] == context.plans.plan_pro_sanbase.name
    end

    test "subscribe to SanAPI PRO plan doesn't give free trial", context do
      query = subscribe_mutation(context.plans.plan_pro.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert response["plan"]["name"] == context.plans.plan_pro.name
    end

    test "subscribe when already subscribed to this plan", context do
      insert(:subscription_pro_sanbase, status: :active, user: context.user)

      capture_log(fn ->
        query = subscribe_mutation(context.plans.plan_pro_sanbase.id)
        error_msg = execute_mutation_with_error(context.conn, query)
        assert error_msg =~ "You are already subscribed to Sanbase by Santiment / PRO"
      end)
    end
  end

  describe "update_subscription mutation" do
    test "successfully upgrade plan from ESSENTIAL to PRO", context do
      subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
      query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)
      response = execute_mutation(context.conn, query, "updateSubscription")

      assert response["plan"]["name"] == context.plans.plan_pro.name
    end

    test "returns error if subscription is scheduled for cancellation", context do
      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          cancel_at_period_end: true,
          current_period_end: Timex.now()
        )

      query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Subscription is scheduled for cancellation at the end of the paid period"
             end) =~ "Subscription is scheduled for cancellation at the end of the paid period"
    end

    test "when not existing plan provided - returns proper error", context do
      subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
      query = update_subscription_mutation(subscription.id, -1)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cannot find plan with id -1"
             end) =~ "Cannot find plan with id -1"
    end

    test "when not existing subscription provided - returns proper error", context do
      query = update_subscription_mutation(-1, context.plans.plan_pro.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~ "Cannot find subscription with id -1"
             end) =~ "Cannot find subscription with id -1"
    end

    test "when updating not own subscription - returns error", context do
      user2 = insert(:user)

      subscription = insert(:subscription_essential, user: user2, stripe_id: "stripe_id")

      query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cannot find subscription with id #{subscription.id} for user with id #{context.user.id}. Either this subscription doesn not exist or it does not belong to the user."
             end) =~ "Cannot find subscription with id"
    end

    test "when retrieving subscription from Stripe fails - returns generic error", context do
      with_mock StripeApi, [],
        update_subscription_item_by_id: fn _, _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
        query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end

    test "when updating subscription in Stripe fails - returns generic error", context do
      with_mock Sanbase.StripeApi, [],
        update_subscription_item_by_id: fn _, _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
        query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end
  end

  describe "cancel_subscription mutation" do
    test "successfully cancel subscription", context do
      period_end = Timex.shift(Timex.now(), days: 3) |> DateTime.truncate(:second)

      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          current_period_end: period_end
        )

      self = self()
      ref = make_ref()

      Sanbase.Mock.prepare_mock(
        Sanbase.Notifications.Discord,
        :send_notification,
        fn _, _, payload ->
          send(self, {ref, payload})
          :ok
        end
      )
      |> Sanbase.Mock.run_with_mocks(fn ->
        query = cancel_subscription_mutation(subscription.id)
        response = execute_mutation(context.conn, query, "cancelSubscription")

        assert response["isScheduledForCancellation"]

        assert response["scheduledForCancellationAt"] == DateTime.to_iso8601(period_end)

        assert_receive({^ref, msg}, 1000)

        # The subscription lastest a few seconds and it has 2 days, 23 hours left,
        # so this is rounded to just 2 days. The messages are an approxiamation
        # and does not change the behaviour in any way
        assert msg =~ "New cancellation scheduled for `#{period_end}`"
        assert msg =~ "Subscription status before cancellation: `active`"
        assert msg =~ "Subscription time left: 2 days"
        assert msg =~ "Subscription lasted: 0 days"
      end)
    end

    test "returns error if subscription is scheduled for cancellation", context do
      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          cancel_at_period_end: true,
          current_period_end: Timex.now()
        )

      query = cancel_subscription_mutation(subscription.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Subscription is scheduled for cancellation at the end of the paid period"
             end) =~ "Subscription is scheduled for cancellation at the end of the paid period"
    end

    test "when cancelling not own subscription - returns error", context do
      user2 = insert(:user)

      subscription = insert(:subscription_essential, user: user2, stripe_id: "stripe_id")

      query = cancel_subscription_mutation(subscription.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cannot find subscription with id #{subscription.id} for user with id #{context.user.id}. Either this subscription doesn not exist or it does not belong to the user."
             end) =~ "Cannot find subscription with id"
    end

    test "when not existing subscription provided - returns proper error", context do
      query = cancel_subscription_mutation(-1)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~ "Cannot find subscription with id -1"
             end) =~ "Cannot find subscription with id -1"
    end

    test "when updating subscription in Stripe fails - returns generic error", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [
           cancel_subscription: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
        query = cancel_subscription_mutation(subscription.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end
  end

  describe "renew_cancelled_subscription mutation" do
    test "successfully renew subscription", context do
      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          cancel_at_period_end: true,
          current_period_end: Timex.shift(Timex.now(), days: 10)
        )

      query = renew_cancelled_subscription_mutation(subscription.id)
      response = execute_mutation(context.conn, query, "renewCancelledSubscription")

      assert response["cancelAtPeriodEnd"] == false
    end

    test "when subscription is not scheduled for cancellation - returns error", context do
      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          cancel_at_period_end: false,
          current_period_end: Timex.shift(Timex.now(), days: -1)
        )

      query = renew_cancelled_subscription_mutation(subscription.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Subscription is not scheduled for cancellation so it cannot be renewed"
             end) =~
               "Subscription is not scheduled for cancellation so it cannot be renewed"
    end

    test "when not existing subscription provided - returns error", context do
      query = update_subscription_mutation(-1, context.plans.plan_pro.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~ "Cannot find subscription with id -1"
             end) =~ "Cannot find subscription with id -1"
    end

    test "when renewing not own subscription - returns error", context do
      user2 = insert(:user)

      subscription =
        insert(:subscription_essential,
          user: user2,
          stripe_id: "stripe_id",
          cancel_at_period_end: true,
          current_period_end: Timex.shift(Timex.now(), days: -1)
        )

      query = renew_cancelled_subscription_mutation(subscription.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cannot find subscription with id #{subscription.id} for user with id #{context.user.id}. Either this subscription doesn not exist or it does not belong to the user."
             end) =~ "Cannot find subscription with id"
    end

    test "when renewing subscription after end period - returns error", context do
      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          cancel_at_period_end: true,
          current_period_end: Timex.shift(Timex.now(), days: -1)
        )

      query = renew_cancelled_subscription_mutation(subscription.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cancelled subscription has already reached the end period"
             end) =~ "Cancelled subscription has already reached the end period"
    end

    test "when updating subscription in Stripe fails - returns generic error", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [
           update_subscription: fn _, _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        subscription =
          insert(:subscription_essential,
            user: context.user,
            stripe_id: "stripe_id",
            cancel_at_period_end: true,
            current_period_end: Timex.shift(Timex.now(), days: 10)
          )

        query = renew_cancelled_subscription_mutation(subscription.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg =~ "test error"
               end) =~ "test error"
      end
    end
  end

  defp check_coupon(coupon) do
    """
    {
      getCoupon(coupon: "#{coupon}") {
        isValid
        id
        name
        amountOff
        percentOff
      }
    }
    """
  end

  defp current_user_query do
    """
    {
      currentUser {
        subscriptions {
          plan {
            id
            name
            product {
              name
            }
          }
        }
      }
    }
    """
  end

  defp products_with_plans_query() do
    """
    {
      productsWithPlans {
        name
        plans {
          name
        }
      }
    }
    """
  end

  defp subscribe_mutation(plan_id) do
    """
    mutation {
      subscribe(card_token: "card_token", plan_id: #{plan_id}) {
        id,
        status
        plan {
          id
          name
          interval
          amount
          product {
            name
          }
        }
      }
    }
    """
  end

  defp subscribe_with_coupon_mutation(plan_id, coupon) do
    """
    mutation {
      subscribe(card_token: "card_token", plan_id: #{plan_id}, coupon: "#{coupon}") {
        id,
        status
        plan {
          id
          name
          interval
          amount
          product {
            name
          }
        }
      }
    }
    """
  end

  defp update_subscription_mutation(subscription_id, plan_id) do
    """
    mutation {
      updateSubscription(subscriptionId: #{subscription_id}, planId: #{plan_id}) {
        plan {
          id
          name
          interval
          amount
          product {
            id
            name
          }
        }
      }
    }
    """
  end

  defp renew_cancelled_subscription_mutation(subscription_id) do
    """
    mutation {
      renewCancelledSubscription(subscriptionId: #{subscription_id}) {
        currentPeriodEnd
        cancelAtPeriodEnd
      }
    }
    """
  end

  defp cancel_subscription_mutation(subscription_id) do
    """
    mutation {
      cancelSubscription(subscriptionId: #{subscription_id}) {
        isScheduledForCancellation
        scheduledForCancellationAt
      }
    }
    """
  end

  defp update_customer_card() do
    """
    mutation {
      updateDefaultPaymentInstrument(cardToken: "token")
    }
    """
  end

  defp delete_customer_card() do
    """
    mutation {
      deleteDefaultPaymentInstrument
    }
    """
  end
end
