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
     [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]}
  ]) do
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

  test "list products with plans", context do
    query = products_with_plans_query()

    result =
      context.conn
      |> execute_query(query, "productsWithPlans")
      |> hd()

    assert result["name"] == "SanbaseAPI"
    assert length(result["plans"]) == 3
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

               assert error_msg =~ "Cannnot find plan with id -1"
             end) =~ "Cannnot find plan with id -1"
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
          product {
            name
          }
        }
      }
    }
    """
  end
end
