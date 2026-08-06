defmodule Sanbase.StripeApiTest do
  use Sanbase.DataCase, async: false

  import Mock
  import Sanbase.Factory

  alias Sanbase.StripeApi

  describe "attach_payment_method_to_customer" do
    # A payment method that is attached but not made the default is not used by an
    # off-session charge, so the first invoice of a subscription created right
    # after this call would fail with no default payment method.
    test "makes the attached payment method the customer's default" do
      user = insert(:user, stripe_customer_id: "cus_attach_test")
      pm = payment_method("pm_new", "fingerprint_1")

      with_mocks stripe_mocks(payment_methods: [pm, payment_method("pm_old", "fingerprint_1")]) do
        assert {:ok, ^user} = StripeApi.attach_payment_method_to_customer(user, "pm_new")

        assert calls(:attach) == [{"pm_new", %{customer: "cus_attach_test"}}]

        assert calls(:update_customer) == [
                 {"cus_attach_test", %{invoice_settings: %{default_payment_method: "pm_new"}}}
               ]

        # The same card attached a second time leaves a duplicate behind.
        assert calls(:detach) == ["pm_old"]
      end
    end

    test "returns a refused payment method as an error instead of raising" do
      user = insert(:user, stripe_customer_id: "cus_declined_test")

      declined = %Stripe.Error{
        source: :stripe,
        code: :card_declined,
        message: "Your card was declined."
      }

      with_mocks stripe_mocks(attach: {:error, declined}) do
        assert {:error, ^declined} = StripeApi.attach_payment_method_to_customer(user, "pm_bad")

        # Nothing is made the default when nothing was attached.
        assert calls(:update_customer) == []
      end
    end
  end

  defp stripe_mocks(opts) do
    attach_result = Keyword.get(opts, :attach)
    payment_methods = Keyword.get(opts, :payment_methods, [])

    [
      {Stripe.PaymentMethod, [],
       [
         attach: fn payment_method_id, params ->
           record(:attach, {payment_method_id, params})

           attach_result || {:ok, payment_method(payment_method_id, "fingerprint_1")}
         end,
         retrieve: fn payment_method_id ->
           {:ok, payment_method(payment_method_id, "fingerprint_1")}
         end,
         list: fn _params -> {:ok, %Stripe.List{data: payment_methods}} end,
         detach: fn payment_method_id ->
           record(:detach, payment_method_id)
           {:ok, payment_method(payment_method_id, "fingerprint_1")}
         end
       ]},
      {Stripe.Customer, [],
       [
         update: fn stripe_customer_id, params ->
           record(:update_customer, {stripe_customer_id, params})
           {:ok, %Stripe.Customer{id: stripe_customer_id}}
         end
       ]}
    ]
  end

  defp payment_method(id, fingerprint) do
    %Stripe.PaymentMethod{id: id, card: %{fingerprint: fingerprint}}
  end

  defp record(key, value) do
    Process.put({:stripe_calls, key}, [value | Process.get({:stripe_calls, key}, [])])
  end

  defp calls(key), do: Process.get({:stripe_calls, key}, []) |> Enum.reverse()
end
