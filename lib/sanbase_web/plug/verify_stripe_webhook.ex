defmodule SanbaseWeb.Plug.VerifyStripeWebhook do
  @moduledoc ~s"""
  Verify the events that Stripe sends to our webhook endpoint.

  This plug should be placed before Plug.Parsers because it needs to read the raw body.
  It only verifies signature if the path matches the stripe webhook path, otherwise it skips.
  Upon succesfull verification of the signature the event map is preserved in conn.assigns[:stripe_event]
  which can be later used by the appropriate controller method.

  Stripe docs: https://stripe.com/docs/webhooks/signatures
  """
  @behaviour Plug

  import Plug.Conn

  require Logger
  alias Sanbase.Utils.Config

  def init(opts), do: opts

  def call(conn, _opts), do: verify_stripe_request(conn)

  defp verify_stripe_request(conn) do
    case conn.path_info do
      ["stripe_webhook"] ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        do_verify(conn, body)

      _ ->
        conn
    end
  end

  defp do_verify(conn, body) do
    secret = webhook_secret()

    with [signature] <- get_req_header(conn, "stripe-signature"),
         true <- is_binary(secret) and byte_size(secret) > 0,
         {:ok, %Stripe.Event{}} <-
           Sanbase.StripeApi.Webhook.construct_event(body, signature, secret) do
      conn
      |> assign(:stripe_event, Jason.decode!(body))
    else
      {:error, error} ->
        halt_and_log_error(conn, error)

      _ ->
        halt_and_log_error(conn, "missing stripe-signature header or webhook secret")
    end
  end

  defp halt_and_log_error(conn, error) do
    Logger.error("Error verifying stripe event reason: #{error}")

    conn
    |> send_resp(:bad_request, "Request signature not verified")
    |> halt()
  end

  defp webhook_secret(), do: Config.module_get(__MODULE__, :webhook_secret)
end
