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
       send_notification: fn _, _, _ -> :ok end,
       encode!: fn _, _ -> "{}" end
     ]}
  ]) do
    clean_task_supervisor_children()

    user = insert(:user)
    {:ok, user: user}
  end

  describe "charge.failed event" do
    test "handle charged.failed event",
         context do
      {:ok, %Stripe.Subscription{id: stripe_id}} =
        StripeApiTestResponse.retrieve_subscription_resp(stripe_id: @stripe_id)

      insert(:subscription_essential, user: context.user, stripe_id: stripe_id)

      payload = charge_failed_json()
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
        response = post_stripe_webhook(:charge_failed)

        assert_receive({_, {:ok, %StripeEvent{is_processed: true}}}, 1000)

        assert StripeEvent |> Repo.all() |> hd() |> Map.get(:event_id) ==
                 Jason.decode!(payload) |> Map.get("id")

        assert response.status == 200

        assert_receive({^ref, msg}, 1000)

        assert msg =~ "⛔ Failed card charge for $529"

        assert msg =~
                 "Details: Your card was declined. The bank did not return any further details with this decline."

        assert msg =~ "Event: https://dashboard.stripe.com/events/evt_1Eud0qCA0hGU8IEVdOgcTrft"
      end)
    end
  end

  describe "invoice.payment_succeeded event" do
    test "when event with id that doesn't exist - create and process event successfully",
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

    test "when event with this id exists - return 200 and don't process", context do
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

        :payment_failed ->
          payment_failed_json()

        :charge_failed ->
          charge_failed_json()
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
    :crypto.mac(:hmac, :sha256, secret, payload)
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
          "tax_rate": null,
          "trial_end": null,
          "trial_start": null
        }
      }
    }
    """
  end

  defp charge_failed_json do
    """
    {
      "created": 1326853478,
      "livemode": false,
      "id": "evt_1Eud0qCA0hGU8IEVdOgcTrft",
      "type": "charge.failed",
      "object": "event",
      "request": null,
      "pending_webhooks": 1,
      "api_version": "2017-08-15",
      "data": {
        "object": {
          "id": "ch_1I",
          "object": "charge",
          "amount": 52900,
          "amount_captured": 0,
          "amount_refunded": 0,
          "application": null,
          "application_fee": null,
          "application_fee_amount": null,
          "balance_transaction": null,
          "billing_details": {
            "address": {
              "city": null,
              "country": null,
              "line1": null,
              "line2": null,
              "postal_code": null,
              "state": null
            },
            "email": null,
            "name": null,
            "phone": null
          },
          "calculated_statement_descriptor": "SANTIMENT",
          "captured": false,
          "created": 1620980672,
          "currency": "usd",
          "customer": "cus_JTd44randstuff",
          "description": "Subscription creation",
          "destination": null,
          "dispute": null,
          "disputed": false,
          "failure_code": "card_declined",
          "failure_message": "Your card was declined.",
          "fraud_details": {
          },
          "invoice": "in_1IqfqYCA0hGU8IEVShG79rS5",
          "livemode": false,
          "metadata": {
          },
          "on_behalf_of": null,
          "order": null,
          "outcome": {
            "network_status": "declined_by_network",
            "reason": "generic_decline",
            "risk_level": "normal",
            "risk_score": 34,
            "seller_message": "The bank did not return any further details with this decline.",
            "type": "issuer_declined"
          },
          "paid": false,
          "payment_intent": "pi_1IqfqYCA0hGU8IEVrandstuff",
          "payment_method": "card_1IqwJ6CA0hGU8Irandstuff",
          "payment_method_details": {
            "card": {
              "brand": "visa",
              "checks": {
                "address_line1_check": null,
                "address_postal_code_check": null,
                "cvc_check": "pass"
              },
              "country": "US",
              "exp_month": 1,
              "exp_year": 2022,
              "fingerprint": "vQb5YIkrandstuff",
              "funding": "credit",
              "installments": null,
              "last4": "0341",
              "network": "visa",
              "three_d_secure": null,
              "wallet": null
            },
            "type": "card"
          },
          "receipt_email": "test@gsantiment.net",
          "receipt_number": null,
          "receipt_url": null,
          "refunded": false,
          "refunds": {
            "object": "list",
            "data": [
            ],
            "has_more": false,
            "total_count": 0,
            "url": "/v1/charges/ch_1IqwJwCA0hGrandstuff/refunds"
          },
          "review": null,
          "shipping": null,
          "source": {
            "id": "card_1IqwJ6CA0hrandstuff",
            "object": "card",
            "address_city": null,
            "address_country": null,
            "address_line1": null,
            "address_line1_check": null,
            "address_line2": null,
            "address_state": null,
            "address_zip": null,
            "address_zip_check": null,
            "brand": "Visa",
            "country": "US",
            "customer": "cus_JTd44gNrandstuff",
            "cvc_check": "pass",
            "dynamic_last4": null,
            "exp_month": 1,
            "exp_year": 2022,
            "fingerprint": "vQb5YIkbranfstuff",
            "funding": "credit",
            "last4": "0341",
            "metadata": {
            },
            "name": null,
            "tokenization_method": null
          },
          "source_transfer": null,
          "statement_descriptor": null,
          "statement_descriptor_suffix": null,
          "status": "failed",
          "transfer_data": null,
          "transfer_group": null
        }
      }
    }
    """
  end

  defp payment_failed_json do
    """
    {
      "created": 1326853478,
      "livemode": false,
      "id": "evt_1Eud0qCA0hGU8IEVdOgcTrft",
      "type": "invoice.payment_failed",
      "object": "event",
      "request": null,
      "pending_webhooks": 1,
      "api_version": "2017-08-15",
      "data": {
        "object": {
          "id": "evt_1alsdljasl921j",
          "object": "invoice",
          "amount": 1000,
          "amount_due": 0,
          "application_fee": null,
          "attempt_count": 0,
          "attempted": true,
          "billing": "charge_automatically",
          "charge": null,
          "closed": false,
          "currency": "usd",
          "customer": "cus_00000000000000",
          "date": 1505770975,
          "description": null,
          "discount": null,
          "ending_balance": null,
          "forgiven": false,
          "lines": {
            "data": [
              {
                "id": "sub_BQNmhjeDUv5aw0",
                "object": "line_item",
                "amount": 999,
                "currency": "usd",
                "description": null,
                "discountable": true,
                "livemode": true,
                "metadata": {
                },
                "period": {
                  "start": 1508362975,
                  "end": 1511041375
                },
                "plan": {
                  "id": "vwv3ww",
                  "object": "plan",
                  "amount": 19900,
                  "created": 1407112740,
                  "currency": "usd",
                  "interval": "month",
                  "interval_count": 1,
                  "livemode": false,
                  "metadata": {
                  },
                  "name": "Analytics",
                  "statement_descriptor": null,
                  "trial_period_days": null
                },
                "proration": false,
                "quantity": 1,
                "subscription": "#{@stripe_id}",
                "subscription_item": "si_1B3X112eZvKYlo2CIQmgTwPZ",
                "type": "subscription"
              }
            ],
            "total_count": 1,
            "object": "list",
            "url": "/v1/invoices/in_BQNmR26copjyyy/lines"
          },
          "livemode": false,
          "metadata": {
          },
          "next_payment_attempt": 1505774575,
          "number": "17d12e06df-0001",
          "paid": false,
          "period_end": 1505770975,
          "period_start": 1505770975,
          "receipt_number": null,
          "starting_balance": 0,
          "statement_descriptor": null,
          "subscription": "#{@stripe_id}",
          "subtotal": 0,
          "tax": null,
          "tax_rate": null,
          "webhooks_delivered_at": null
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
          "tax_rate": null,
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
