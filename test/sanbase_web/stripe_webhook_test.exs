defmodule SanbaseWeb.StripeWebhookTest do
  use SanbaseWeb.ConnCase, async: false

  import Mock
  import Sanbase.Factory
  import Sanbase.TestHelpers
  import ExUnit.CaptureLog

  alias Sanbase.Billing.StripeEvent
  alias Sanbase.Repo
  alias Sanbase.StripeApiTestReponse
  alias Sanbase.StripeApi

  setup_with_mocks([
    {StripeApi, [],
     [retrieve_subscription: fn _ -> StripeApiTestReponse.retrieve_subscription_resp() end]}
  ]) do
    clean_task_supervisor_children()

    Sanbase.Billing.TestSeed.seed_products_and_plans()

    user = insert(:user)
    {:ok, user: user}
  end

  describe "invoice.payment_succeeded event" do
    test "when event with this id doesn't exist - create and process event successfully",
         context do
      {:ok, %Stripe.Subscription{id: stripe_id}} =
        StripeApiTestReponse.retrieve_subscription_resp()

      insert(:subscription_essential,
        user: context.user,
        stripe_id: stripe_id
      )

      payload = json_payload()
      response = post_stripe_webhook()

      assert_receive({_, {:ok, %StripeEvent{is_processed: true}}})

      assert StripeEvent |> Repo.all() |> hd() |> Map.get(:event_id) ==
               Jason.decode!(payload) |> Map.get("id")

      assert response.status == 200
    end

    test "when event with this id exists - return 200 and don't process",
         context do
      payload = json_payload()
      StripeEvent.create(Jason.decode!(payload))

      {:ok, %Stripe.Subscription{id: stripe_id}} =
        StripeApiTestReponse.retrieve_subscription_resp()

      insert(:subscription_essential,
        user: context.user,
        stripe_id: stripe_id
      )

      response = post_stripe_webhook()

      refute_receive({_, {:ok, %StripeEvent{is_processed: true}}})
      assert response.status == 200
    end

    test "when signature signed with wrong secret - returns not valid message" do
      payload = json_payload()

      capture_log(fn ->
        response =
          build_conn()
          |> put_req_header("content-type", "application/json")
          |> put_req_header("stripe-signature", signature_header(payload, "wrong secret"))
          |> post("/stripe_webhook", payload)

        refute_receive({_, {:ok, %StripeEvent{is_processed: true}}})
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
          response = post_stripe_webhook()

          refute_receive({_, {:ok, %StripeEvent{is_processed: true}}})
          assert response.status == 200
        end)
      end
    end
  end

  defp post_stripe_webhook do
    payload = json_payload()

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

  defp json_payload do
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
              "name": null,
              "percent_off": 20,
              "redeem_by": null,
              "times_redeemed": 1,
              "valid": true
            },
            "customer": "cus_FPRuty3TVaGwlW",
            "end": null,
            "start": 1562754419,
            "subscription": "sub_FPRuTYbI28tACT"
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
                "description": "1 × SANapi (at $119.00 / month)",
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
                "subscription": "sub_FPRuTYbI28tACT",
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
          "subscription": "sub_FPRuTYbI28tACT",
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
