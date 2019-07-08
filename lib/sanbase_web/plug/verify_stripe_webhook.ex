defmodule SanbaseWeb.Plug.VerifyStripeWebhook do
  @moduledoc ~s"""
  Verify the events that Stripe sends to our webhook endpoint.

  https://stripe.com/docs/webhooks/signatures
  """
  @behaviour Plug

  import Plug.Conn

  require Logger
  require Sanbase.Utils.Config, as: Config

  def init(opts), do: opts

  def call(conn, _opts), do: verify_stripe_request(conn)

  defp verify_stripe_request(conn) do
    do_verify(conn, conn.private[:raw_body])
  end

  defp do_verify(conn, body) do
    [signature] = get_req_header(conn, "stripe-signature")

    case Stripe.Webhook.construct_event(body, signature, webhook_secret()) do
      {:ok, %Stripe.Event{} = event} ->
        conn
        |> assign(:stripe_event, event)

      {:error, error} ->
        halt_and_log_error(conn, error)
    end
  end

  defp halt_and_log_error(conn, error) do
    Logger.error("Error verifying stripe event reason: #{error}")

    conn
    |> send_resp(:bad_request, "Request signature not verified")
    |> halt()
  end

  defp webhook_secret(), do: Config.get(:webhook_secret)
end
