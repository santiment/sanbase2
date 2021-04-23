defmodule SanbaseWeb.StripeWebhookTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog
  import Ecto.Query

  alias Sanbase.Billing.{StripeEvent, Plan, Subscription}
  alias Sanbase.Repo
  alias Sanbase.StripeApiTestResponse
  alias Sanbase.StripeApi

  @stripe_id "sub_1234567891"

  setup_with_mocks([
    {StripeApi, [],
     [
       retrieve_subscription: fn stripe_id ->
         StripeApiTestResponse.retrieve_subscription_resp(stripe_id: stripe_id)
       end
     ]},
    {Sanbase.Notifications.Discord, [],
     [
       send_notification: fn _, _, _ ->
         :ok
       end,
       encode!: fn _, _ -> "{}" end
     ]}
  ]) do
    clean_task_supervisor_children()

    user = insert(:user)
    {:ok, user: user}
  end

  describe "invoice.payment_succeeded event" do
    test "when event with this id doesn't exist - create and process event successfully",
         context do
      {:ok, %Stripe.Subscription{id: stripe_id}} =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: @stripe_id)

      insert(:subscription_essential,
        user: context.user,
        stripe_id: stripe_id
      )

      payload = payment_succeded_json()
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
        response = post_stripe_webhook(:payment_succeded)

        assert_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)

        assert StripeEvent |> Repo.all() |> hd() |> Map.get(:event_id) ==
                 Jason.decode!(payload) |> Map.get("id")

        assert response.status == 200

        assert_receive({^ref, msg}, 1000)

        assert msg =~ "🎉 New payment for $95 for Neuro by Santiment / ESSENTIAL by"
        assert msg =~ "@santiment.net"
        assert msg =~ "Coupon name: TestSanCoupon"
        assert msg =~ "Coupon id: CVXvPaMG"
        assert msg =~ "Coupon percent off: 20"
      end)
    end

    test "when event with this id exists - return 200 and don't process",
         context do
      payment_succeded_json()
      |> Jason.decode!()
      |> StripeEvent.create()

      {:ok, %Stripe.Subscription{id: stripe_id}} =
        StripeApiTestResponse.retrieve_subscription_resp()

      insert(:subscription_essential,
        user: context.user,
        stripe_id: stripe_id
      )

      response = post_stripe_webhook(:payment_succeded)

      refute_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)
      assert response.status == 200
    end

    test "when signature signed with wrong secret - returns not valid message" do
      payload = payment_succeded_json()

      capture_log(fn ->
        response =
          build_conn()
          |> put_req_header("content-type", "application/json")
          |> put_req_header(
            "stripe-signature",
            signature_header(payload, "wrong secret")
          )
          |> post("/stripe_webhook", payload)

        refute_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)
        refute response.status == 200
        assert response.resp_body =~ "Request signature not verified"
      end)
    end

    test "return 200 and leave unprocessed when event is persisted in db, but error occurs while processing" do
      with_mocks([
        {StripeApi, [],
         [
           retrieve_subscription: fn _ ->
             {:error, %Stripe.Error{message: "test error", source: "ala", code: "bala"}}
           end
         ]}
      ]) do
        capture_log(fn ->
          response = post_stripe_webhook(:payment_succeded)

          refute_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)
          assert response.status == 200
        end)
      end
    end
  end

  describe "customer.subscription.created event" do
    test "successfully create subscription" do
      {:ok, %Stripe.Subscription{customer: stripe_customer_id}} =
        StripeApiTestResponse.retrieve_subscription_resp()

      user = insert(:user, stripe_customer_id: stripe_customer_id)
      response = post_stripe_webhook(:subscription_created)

      assert_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)
      assert response.status == 200

      assert from(s in Subscription, where: s.user_id == ^user.id)
             |> Repo.all()
             |> length() == 1
    end

    test "when there is existing subscription with the same stripe_id - event is processed succesfully, new subscription is not created" do
      {:ok,
       %Stripe.Subscription{
         customer: stripe_customer_id
       }} = StripeApiTestResponse.retrieve_subscription_resp()

      user = insert(:user, stripe_customer_id: stripe_customer_id)

      insert(:subscription_essential,
        user: user,
        stripe_id: @stripe_id
      )

      response = post_stripe_webhook(:subscription_created)

      assert_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)
      assert response.status == 200

      assert from(s in Subscription, where: s.user_id == ^user.id)
             |> Repo.all()
             |> length() == 1
    end

    test "when customer does not exist - subscription is not created" do
      user = insert(:user)

      expected_error_msg = "Customer for subscription_id #{@stripe_id} does not exist"

      capture_log(fn ->
        response = post_stripe_webhook(:subscription_created)

        assert_receive({_, {:error, error_msg}}, 1000)
        assert error_msg =~ expected_error_msg
        assert response.status == 200
      end) =~ expected_error_msg

      assert from(s in Subscription, where: s.user_id == ^user.id)
             |> Repo.all()
             |> length() == 0
    end

    test "when plan does not exist - subscription is not created" do
      {:ok,
       %Stripe.Subscription{
         id: _stripe_id,
         customer: stripe_customer_id,
         plan: %Stripe.Plan{id: stripe_plan_id}
       }} = StripeApiTestResponse.retrieve_subscription_resp()

      Plan.by_stripe_id(stripe_plan_id)
      |> Plan.changeset(%{stripe_id: "non_existing"})
      |> Repo.update!()

      user = insert(:user, stripe_customer_id: stripe_customer_id)

      expected_error_msg = "Plan for subscription_id #{@stripe_id} does not exist"

      capture_log(fn ->
        response = post_stripe_webhook(:subscription_created)

        assert_receive({_, {:error, error_msg}}, 1000)
        assert error_msg =~ expected_error_msg
        assert response.status == 200
      end) =~ expected_error_msg

      assert from(s in Subscription, where: s.user_id == ^user.id)
             |> Repo.all()
             |> length() == 0
    end
  end

  defp post_stripe_webhook(event) do
    payload =
      case event do
        :payment_succeded ->
          payment_succeded_json()

        :subscription_created ->
          subscription_created_json()
      end

    build_conn()
    |> put_req_header("content-type", "application/json")
    |> put_req_header("stripe-signature", signature_header(payload, secret()))
    |> post("/stripe_webhook", payload)
  end

  defp signature_header(payload, secret) do
    timestamp = Timex.now() |> DateTime.to_unix()
    signed_payload = "#{timestamp}.#{payload}"
    signature = compute_signature(signed_payload, secret)

    "t=#{timestamp},v1=#{signature}"
  end

  defp secret do
    "stripe_webhook_secret"
  end

  defp compute_signature(payload, secret) do
    :crypto.hmac(:sha256, secret, payload)
    |> Base.encode16(case: :lower)
  end

  defp subscription_created_json do
    """
    {
      "id": "evt_1Eud0qCA0hGU8IEVdOgcTrft",
      "object": "event",
      "api_version": "2019-02-19",
      "created": 1562754419,
      "type": "customer.subscription.created",
      "livemode": false,
      "pending_webhooks": 1,
      "request": {
        "id": "req_A9TTE0HJ036bgl",
        "idempotency_key": null
      },
      "data": {
        "object": {
          "id": "#{@stripe_id}",
          "object": "subscription",
          "application_fee_percent": null,
          "billing": "charge_automatically",
          "billing_cycle_anchor": 1563889630,
          "billing_thresholds": null,
          "cancel_at": null,
          "cancel_at_period_end": false,
          "canceled_at": null,
          "collection_method": "charge_automatically",
          "created": 1563889630,
          "current_period_end": 1566568030,
          "current_period_start": 1563889630,
          "customer": "cus_FSmndgjh0wSz24",
          "days_until_due": null,
          "default_payment_method": null,
          "default_source": null,
          "default_tax_rates": [
          ],
          "discount": {
            "object": "discount",
            "coupon": {
              "id": "PFXt9JdU",
              "object": "coupon",
              "amount_off": null,
              "created": 1563889630,
              "currency": null,
              "duration": "forever",
              "duration_in_months": null,
              "livemode": false,
              "max_redemptions": null,
              "metadata": {
              },
              "name": "Test Coupon",
              "percent_off": 20,
              "redeem_by": null,
              "times_redeemed": 1,
              "valid": true
            },
            "customer": "cus_FSmndgjh0wSz24",
            "end": null,
            "start": 1563889630,
            "subscription": "#{@stripe_id}"
          },
          "ended_at": null,
          "items": {
            "object": "list",
            "data": [
              {
                "id": "si_FUN45qx35cmYgh",
                "object": "subscription_item",
                "billing_thresholds": null,
                "created": 1563889630,
                "metadata": {
                },
                "plan": {
                  "id": "plan_FJVlH8O0qGs1TM",
                  "object": "plan",
                  "active": true,
                  "aggregate_usage": null,
                  "amount": 11900,
                  "billing_scheme": "per_unit",
                  "created": 1561384894,
                  "currency": "usd",
                  "interval": "month",
                  "interval_count": 1,
                  "livemode": false,
                  "metadata": {
                  },
                  "nickname": "ESSENTIAL",
                  "product": "prod_FJVky7lugU5m6C",
                  "tiers": null,
                  "tiers_mode": null,
                  "transform_usage": null,
                  "trial_period_days": null,
                  "usage_type": "licensed"
                },
                "quantity": 1,
                "subscription": "#{@stripe_id}",
                "tax_rates": [
                ]
              }
            ],
            "has_more": false,
            "total_count": 1,
            "url": "/v1/subscription_items?subscription=#{@stripe_id}"
          },
          "latest_invoice": "in_1EzOKgCA0hGU8IEVn1Gyk4yL",
          "livemode": false,
          "metadata": {
          },
          "pending_setup_intent": null,
          "plan": {
            "id": "plan_FJVlH8O0qGs1TM",
            "object": "plan",
            "active": true,
            "aggregate_usage": null,
            "amount": 11900,
            "billing_scheme": "per_unit",
            "created": 1561384894,
            "currency": "usd",
            "interval": "month",
            "interval_count": 1,
            "livemode": false,
            "metadata": {
            },
            "nickname": "ESSENTIAL",
            "product": "prod_FJVky7lugU5m6C",
            "tiers": null,
            "tiers_mode": null,
            "transform_usage": null,
            "trial_period_days": null,
            "usage_type": "licensed"
          },
          "quantity": 1,
          "schedule": null,
          "start": 1563889630,
          "start_date": 1563889630,
          "status": "active",
          "tax_percent": null,
          "trial_end": null,
          "trial_start": null
        }
      }
    }
    """
  end

  defp payment_succeded_json do
    """
    {
      "id": "evt_1Eud0qCA0hGU8IEVdOgcTrft",
      "object": "event",
      "api_version": "2019-02-19",
      "created": 1562754419,
      "data": {
        "object": {
          "id": "in_1Eud0pCA0hGU8IEVG2LrSogl",
          "object": "invoice",
          "account_country": "CH",
          "account_name": "Santiment GmbH",
          "amount_due": 9520,
          "amount_paid": 9520,
          "amount_remaining": 0,
          "application_fee": null,
          "attempt_count": 1,
          "attempted": true,
          "auto_advance": false,
          "billing": "charge_automatically",
          "billing_reason": "subscription_create",
          "charge": "ch_1Eud0pCA0hGU8IEVLwA6CVfT",
          "collection_method": "charge_automatically",
          "created": 1562754419,
          "currency": "usd",
          "custom_fields": null,
          "customer": "cus_FPRuty3TVaGwlW",
          "customer_address": null,
          "customer_email": "tsvetozar.penov@gmail.com",
          "customer_name": null,
          "customer_phone": null,
          "customer_shipping": null,
          "customer_tax_exempt": "none",
          "customer_tax_ids": [
          ],
          "date": 1562754419,
          "default_payment_method": null,
          "default_source": null,
          "default_tax_rates": [
          ],
          "description": null,
          "discount": {
            "object": "discount",
            "coupon": {
              "id": "CVXvPaMG",
              "object": "coupon",
              "amount_off": null,
              "created": 1562754418,
              "currency": null,
              "duration": "forever",
              "duration_in_months": null,
              "livemode": false,
              "max_redemptions": null,
              "metadata": {
              },
              "name": "TestSanCoupon",
              "percent_off": 20,
              "redeem_by": null,
              "times_redeemed": 1,
              "valid": true
            },
            "customer": "cus_FPRuty3TVaGwlW",
            "end": null,
            "start": 1562754419,
            "subscription": "#{@stripe_id}"
          },
          "due_date": null,
          "ending_balance": 0,
          "finalized_at": 1562754419,
          "footer": null,
          "hosted_invoice_url": "https://pay.stripe.com/invoice/invst_DymQGTG6xOZjHdROmZc8kPZuPN",
          "invoice_pdf": "https://pay.stripe.com/invoice/invst_DymQGTG6xOZjHdROmZc8kPZuPN/pdf",
          "lines": {
            "object": "list",
            "data": [
              {
                "id": "sli_8f9d9198c18d5b",
                "object": "line_item",
                "amount": 11900,
                "currency": "usd",
                "description": "1 × SanAPI (at $119.00 / month)",
                "discountable": true,
                "livemode": false,
                "metadata": {
                },
                "period": {
                  "end": 1565432819,
                  "start": 1562754419
                },
                "plan": {
                  "id": "plan_FJVlH8O0qGs1TM",
                  "object": "plan",
                  "active": true,
                  "aggregate_usage": null,
                  "amount": 11900,
                  "billing_scheme": "per_unit",
                  "created": 1561384894,
                  "currency": "usd",
                  "interval": "month",
                  "interval_count": 1,
                  "livemode": false,
                  "metadata": {
                  },
                  "nickname": "ESSENTIAL",
                  "product": "prod_FJVky7lugU5m6C",
                  "tiers": null,
                  "tiers_mode": null,
                  "transform_usage": null,
                  "trial_period_days": null,
                  "usage_type": "licensed"
                },
                "proration": false,
                "quantity": 1,
                "subscription": "#{@stripe_id}",
                "subscription_item": "si_FPRupE2T9mzCfW",
                "tax_amounts": [
                ],
                "tax_rates": [
                ],
                "type": "subscription"
              }
            ],
            "has_more": false,
            "total_count": 1,
            "url": "/v1/invoices/in_1Eud0pCA0hGU8IEVG2LrSogl/lines"
          },
          "livemode": false,
          "metadata": {
          },
          "next_payment_attempt": null,
          "number": "F5E5B447-0001",
          "paid": true,
          "payment_intent": "pi_1Eud0pCA0hGU8IEVnQ0deeeY",
          "period_end": 1562754419,
          "period_start": 1562754419,
          "post_payment_credit_notes_amount": 0,
          "pre_payment_credit_notes_amount": 0,
          "receipt_number": null,
          "starting_balance": 0,
          "statement_descriptor": null,
          "status": "paid",
          "status_transitions": {
            "finalized_at": 1562754419,
            "marked_uncollectible_at": null,
            "paid_at": 1562754419,
            "voided_at": null
          },
          "subscription": "#{@stripe_id}",
          "subtotal": 11900,
          "tax": null,
          "tax_percent": null,
          "total": 9520,
          "total_tax_amounts": [
          ],
          "webhooks_delivered_at": null
        }
      },
      "livemode": false,
      "pending_webhooks": 1,
      "request": {
        "id": "req_A9TTE0HJ036bgl",
        "idempotency_key": null
      },
      "type": "invoice.payment_succeeded"
    }
    """
  end
end
