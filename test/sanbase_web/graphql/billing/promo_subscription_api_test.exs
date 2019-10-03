defmodule SanbaseWeb.Graphql.Billing.PromoSubscriprionApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.StripeApi
  alias Sanbase.StripeApiTestReponse

  @coupon_code "test_coupon"
  @error_msg "something happened"

  setup_with_mocks([
    {StripeApi, [:passthrough],
     [create_customer: fn _, _ -> StripeApiTestReponse.create_or_update_customer_resp() end]},
    {StripeApi, [:passthrough],
     [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]},
    {StripeApi, [:passthrough],
     [
       retrieve_coupon: fn _ ->
         {:ok,
          %Stripe.Coupon{
            id: @coupon_code,
            valid: true,
            metadata: %{"current_promotion" => "devcon2019"}
          }}
       end
     ]}
  ]) do
    user = insert(:staked_user)
    conn = setup_jwt_auth(build_conn(), user)

    {:ok, conn: conn, user: user}
  end

  describe "promo subscription mutation" do
    test "with right coupon code successfully creates subscriptions", context do
      query = promo_subscription_mutation(@coupon_code)
      response = execute_mutation(context.conn, query, "createPromoSubscription")
      assert response |> length() == 3
    end

    test "when retrieving this coupon code errors - returns proper error message", context do
      with_mocks([
        {StripeApi, [:passthrough],
         [
           retrieve_coupon: fn _ ->
             {:error, %Stripe.Error{message: @error_msg, source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        query = promo_subscription_mutation("UNUSED")

        capture_log(fn ->
          error_msg = execute_mutation_with_error(context.conn, query)

          assert error_msg == @error_msg
        end)
      end
    end
  end

  test "with invalid/unsupported coupon code returns proper error message", context do
    with_mocks([
      {StripeApi, [:passthrough],
       [
         retrieve_coupon: fn _ ->
           {:ok,
            %Stripe.Coupon{
              id: @coupon_code,
              valid: false
            }}
         end
       ]}
    ]) do
      query = promo_subscription_mutation("UNUSED")

      capture_log(fn ->
        error_msg = execute_mutation_with_error(context.conn, query)

        assert error_msg =~ "The coupon code is not valid"
      end)
    end
  end

  test "creating Stripe customer fails - return proper message", context do
    with_mocks([
      {StripeApi, [:passthrough],
       [
         create_customer: fn _, _ ->
           {:error, %Stripe.Error{message: @error_msg, source: "ala", code: "bala"}}
         end
       ]},
      {StripeApi, [:passthrough],
       [create_subscription: fn _ -> StripeApiTestReponse.create_subscription_resp() end]},
      {StripeApi, [:passthrough],
       [
         retrieve_coupon: fn _ ->
           {:ok,
            %Stripe.Coupon{
              id: @coupon_code,
              valid: true,
              metadata: %{"current_promotion" => "devcon2019"}
            }}
         end
       ]}
    ]) do
      query = promo_subscription_mutation(@coupon_code)

      capture_log(fn ->
        error_msg = execute_mutation_with_error(context.conn, query)

        assert error_msg =~ @error_msg
      end)
    end
  end

  test "creating subscription in Stripe fails - return proper message", context do
    with_mocks([
      {StripeApi, [:passthrough],
       [
         create_customer: fn _, _ ->
           StripeApiTestReponse.create_or_update_customer_resp()
         end
       ]},
      {StripeApi, [:passthrough],
       [
         create_subscription: fn _ ->
           {:error, %Stripe.Error{message: @error_msg, source: "ala", code: "bala"}}
         end
       ]},
      {StripeApi, [:passthrough],
       [
         retrieve_coupon: fn _ ->
           {:ok,
            %Stripe.Coupon{
              id: @coupon_code,
              valid: true,
              metadata: %{"current_promotion" => "devcon2019"}
            }}
         end
       ]}
    ]) do
      query = promo_subscription_mutation(@coupon_code)

      capture_log(fn ->
        error_msg = execute_mutation_with_error(context.conn, query)

        assert error_msg =~ @error_msg
      end)
    end
  end

  defp promo_subscription_mutation(coupon) do
    """
    mutation {
      createPromoSubscription(couponCode: "#{coupon}") {
        plan {
          id
          name
          product {
            name
          }
        }
      }
    }
    """
  end
end
