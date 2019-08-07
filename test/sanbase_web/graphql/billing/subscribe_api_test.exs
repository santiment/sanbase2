defmodule SanbaseWeb.Graphql.Billing.SubscribeApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Auth.User
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestReponse
  alias Sanbase.Billing.Subscription

  setup_with_mocks([
    {StripeApi, [:passthrough],
     [create_product: fn _ -> StripeApiTestReponse.create_product_resp() end]},
    {StripeApi, [:passthrough],
     [create_plan: fn _ -> StripeApiTestReponse.create_plan_resp() end]},
    {StripeApi, [:passthrough],
     [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [update_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [create_coupon: fn _ -> StripeApiTestReponse.create_coupon_resp() end]},
    {StripeApi, [:passthrough],
     [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]},
    {Sanbase.StripeApi, [:passthrough],
     [get_subscription_first_item_id: fn _ -> {:ok, "item_id"} end]},
    {Sanbase.StripeApi, [:passthrough],
     [
       update_subscription: fn _, _ ->
         StripeApiTestReponse.update_subscription_resp()
       end
     ]},
    {Sanbase.StripeApi, [:passthrough],
     [
       cancel_subscription: fn _ ->
         StripeApiTestReponse.update_subscription_resp()
       end
     ]}
  ]) do
    # Needs to be staked to apply the discount
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  test "list products with plans", context do
    query = products_with_plans_query()

    result =
      context.conn
      |> execute_query(query, "productsWithPlans")
      |> hd()

    assert result["name"] == "SANapi"
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
        current_period_end: Timex.shift(Timex.now(), days: -2)
      )

      current_user = execute_query(context.conn, current_user_query(), "currentUser")
      assert current_user["subscriptions"] == []
    end
  end

  describe "subscribe mutation" do
    test "successfull subscribe returns subscription", context do
      query = subscribe_mutation(context.plans.plan_essential.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert response["status"] == "ACTIVE"
      assert response["plan"]["name"] == context.plans.plan_essential.name
    end

    test "successfull subscribe when user has stripe_customer_id", context do
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

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end

    test "when creating coupon fails - logs the error and returns generic error", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
        {StripeApi, [:passthrough],
         [
           create_coupon: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        query = subscribe_mutation(context.plans.plan_essential.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end

    test "when creating subscription in Stripe fails - logs the error and returns generic error",
         context do
      with_mocks([
        {StripeApi, [:passthrough],
         [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
        {StripeApi, [:passthrough],
         [create_coupon: fn _ -> StripeApiTestReponse.create_coupon_resp() end]},
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

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
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
                        "Cannot find subscription with id #{subscription.id} for user with id #{
                          context.user.id
                        }. Either this subscription doesn not exist or it does not belong to the user."
             end) =~ "Cannot find subscription with id"
    end

    test "when retrieving subscription from Stripe fails - returns generic error", context do
      with_mock StripeApi, [],
        get_subscription_first_item_id: fn _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
        query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end

    test "when updating subscription in Stripe fails - returns generic error", context do
      with_mocks([
        {Sanbase.StripeApi, [:passthrough],
         [get_subscription_first_item_id: fn _ -> {:ok, "item_id"} end]},
        {StripeApi, [:passthrough],
         [
           update_subscription: fn _, _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
        query = update_subscription_mutation(subscription.id, context.plans.plan_pro.id)

        assert capture_log(fn ->
                 error_msg = execute_mutation_with_error(context.conn, query)

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end
  end

  describe "cancel_subscription mutation" do
    test "successfully cancel subscription", context do
      tomorrow = Timex.shift(Timex.now(), days: 1)

      subscription =
        insert(:subscription_essential,
          user: context.user,
          stripe_id: "stripe_id",
          current_period_end: tomorrow
        )

      query = cancel_subscription_mutation(subscription.id)
      response = execute_mutation(context.conn, query, "cancelSubscription")

      assert response["isScheduledForCancellation"]

      assert response["scheduledForCancellationAt"] ==
               DateTime.to_iso8601(DateTime.truncate(tomorrow, :second))
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
                        "Cannot find subscription with id #{subscription.id} for user with id #{
                          context.user.id
                        }. Either this subscription doesn not exist or it does not belong to the user."
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

                 assert error_msg == Subscription.generic_error_message()
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
                        "Cannot find subscription with id #{subscription.id} for user with id #{
                          context.user.id
                        }. Either this subscription doesn not exist or it does not belong to the user."
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

                 assert error_msg == Subscription.generic_error_message()
               end) =~ "test error"
      end
    end
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
end
