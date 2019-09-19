defmodule SanbaseWeb.Graphql.Billing.PromoCouponApiTest do
  use SanbaseWeb.ConnCase

  import Sanbase.Factory
  import Mock
  import SanbaseWeb.Graphql.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.StripeApi
  alias Sanbase.MandrillApi

  @coupon_code "test_coupon"
  @promo_percent_off 25
  @test_email "test@example.com"

  setup_with_mocks([
    {MandrillApi, [:passthrough],
     [
       send: fn _, _, _ ->
         {:ok, %{}}
       end
     ]},
    {StripeApi, [:passthrough],
     [
       create_promo_coupon: fn _ ->
         {:ok, %Stripe.Coupon{id: @coupon_code, percent_off: @promo_percent_off}}
       end
     ]},
    {StripeApi, [:passthrough],
     [
       retrieve_coupon: fn _ ->
         {:ok, %Stripe.Coupon{id: @coupon_code, percent_off: @promo_percent_off}}
       end
     ]}
  ]) do
    user = insert(:user, email: @test_email)
    conn = setup_jwt_auth(build_conn(), user)

    conn =
      conn
      |> put_req_header(
        "origin",
        "https://app.santiment.net"
      )

    {:ok, conn: conn, user: user}
  end

  describe "send_promo_coupon mutation" do
    test "successfully sends email", context do
      query = send_promo_coupon_mutation(context.user.email)
      response = execute_mutation(context.conn, query, "sendPromoCoupon")

      assert_called(StripeApi.create_promo_coupon(:_))

      assert_called(
        MandrillApi.send(:_, :_, %{
          "COUPON_CODE" => @coupon_code,
          "DISCOUNT" => @promo_percent_off
        })
      )

      assert response["success"]
    end

    test "when there is a coupon for this email - send it", context do
      insert(:promo_coupon, email: context.user.email, coupon: @coupon_code)
      query = send_promo_coupon_mutation(context.user.email)
      response = execute_mutation(context.conn, query, "sendPromoCoupon")

      assert_called(StripeApi.retrieve_coupon(@coupon_code))
      refute called(StripeApi.create_promo_coupon(:_))

      assert_called(
        MandrillApi.send(:_, :_, %{
          "COUPON_CODE" => @coupon_code,
          "DISCOUNT" => @promo_percent_off
        })
      )

      assert response["success"]
    end

    test "when create coupon in Stripe return error - return success false and logs error",
         context do
      with_mock StripeApi, [:passthrough],
        create_promo_coupon: fn _ ->
          {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
        end do
        query = send_promo_coupon_mutation(context.user.email)

        assert capture_log(fn ->
                 response = execute_mutation(context.conn, query, "sendPromoCoupon")
                 refute response["success"]
               end) =~ "test error"
      end
    end

    test "when send email returns error - return success false and logs error", context do
      with_mock MandrillApi, [:passthrough],
        send: fn _, _, _ ->
          {:error, "test error"}
        end do
        query = send_promo_coupon_mutation(context.user.email)

        assert capture_log(fn ->
                 response = execute_mutation(context.conn, query, "sendPromoCoupon")
                 refute response["success"]
               end) =~ "test error"
      end
    end
  end

  defp send_promo_coupon_mutation(email, message \\ "message") do
    """
    mutation {
      sendPromoCoupon(email: "#{email}", message: "#{message}") {
        success
      }
    }
    """
  end
end
