defmodule SanbaseWeb.Graphql.Pricing.SubscribeApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Auth.Apikey
  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestReponse

  setup_with_mocks([
    {StripeApi, [], [create_product: fn _ -> StripeApiTestReponse.create_product_resp() end]},
    {StripeApi, [], [create_plan: fn _ -> StripeApiTestReponse.create_plan_resp() end]},
    {StripeApi, [],
     [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
    {StripeApi, [],
     [update_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
    {StripeApi, [], [create_coupon: fn _ -> StripeApiTestReponse.create_coupon_resp() end]},
    {StripeApi, [],
     [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]},
    {Sanbase.StripeApi, [], [get_subscription_first_item_id: fn _ -> {:ok, "item_id"} end]},
    {Sanbase.StripeApi, [],
     [
       update_subscription: fn _, _ ->
         StripeApiTestReponse.update_subscription_resp()
       end
     ]},
    {Sanbase.StripeApi, [],
     [
       cancel_subscription: fn _ ->
         StripeApiTestReponse.update_subscription_resp()
       end
     ]}
  ]) do
    free_user = insert(:user)
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    plans = Sanbase.Pricing.TestSeed.seed_products_and_plans()

    {:ok, apikey} = Apikey.generate_apikey(user)
    conn_apikey = setup_apikey_auth(build_conn(), apikey)

    {:ok, apikey_free} = Apikey.generate_apikey(free_user)
    conn_apikey_free = setup_apikey_auth(build_conn(), apikey_free)

    {:ok,
     conn: conn,
     user: user,
     product: plans.product,
     plan_essential: plans.plan_essential,
     plan_pro: plans.plan_pro,
     conn_apikey: conn_apikey,
     conn_apikey_free: conn_apikey_free}
  end

  test "list products with plans", context do
    query = products_with_plans_query()

    result =
      context.conn
      |> execute_query(query, "productsWithPlans")
      |> hd()

    assert result["name"] == "SanbaseAPI"
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
  end

  describe "subscribe mutation" do
    test "successfull subscribe returns subscription", context do
      query = subscribe_mutation(context.plan_essential.id)
      response = execute_mutation(context.conn, query, "subscribe")

      assert response["plan"]["name"] == context.plan_essential.name
    end

    test "unsuccessfull subscribe returns error", context do
      query = subscribe_mutation(-1)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~ "Cannot find plan with id -1"
             end) =~ "Cannot find plan with id -1"
    end
  end

  describe "update_subscription mutation" do
    test "successfully upgrade plan from ESSENTIAL to PRO", context do
      subscription = insert(:subscription_essential, user: context.user, stripe_id: "stripe_id")
      query = update_subscription_mutation(subscription.id, context.plan_pro.id)
      response = execute_mutation(context.conn, query, "updateSubscription")

      assert response["plan"]["name"] == context.plan_pro.name
    end

    test "error when updating not own subscription", context do
      user2 = insert(:user)

      subscription = insert(:subscription_essential, user: user2, stripe_id: "stripe_id")

      query = update_subscription_mutation(subscription.id, context.plan_pro.id)

      assert capture_log(fn ->
               error_msg = execute_mutation_with_error(context.conn, query)

               assert error_msg =~
                        "Cannot find subscription with id #{subscription.id} for user with id #{
                          context.user.id
                        }. Either this subscription doesn not exist or it does not belong to the user."
             end) =~ "Cannot find subscription with id"
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

      assert response["scheduledForCancellation"]
      assert response["scheduledForCancellationAt"] == DateTime.to_iso8601(tomorrow)
    end

    test "error when cancelling not own subscription", context do
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
  end

  defp current_user_query do
    """
    {
      currentUser {
        subscriptions {
          plan {
            id
            name
            access
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
          access
        }
      }
    }
    """
  end

  defp subscribe_mutation(plan_id) do
    """
    mutation {
      subscribe(card_token: "card_token", plan_id: #{plan_id}) {
        plan {
          id
          name
          access
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
          access
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

  defp cancel_subscription_mutation(subscription_id) do
    """
    mutation {
      cancelSubscription(subscriptionId: #{subscription_id}) {
        scheduledForCancellation
        scheduledForCancellationAt
      }
    }
    """
  end
end
