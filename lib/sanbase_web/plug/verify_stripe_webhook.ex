defmodule SanbaseWeb.Plug.VerifyStripeWebhook do
  @moduledoc ~s"""
  Verify the events that Stripe sends to our webhook endpoint.

  This plug should be placed before Plug.Parsers because it needs to read the raw body.
  IT only verifies signature if the `request_path=stripe_webhook_path` otherwise it skips.
  Upon succesfull verification of the signature the event map is preserved in conn.assigns[:stripe_event]
  which can be later used by the appropriate controller method.

  Stripe docs: https://stripe.com/docs/webhooks/signatures
  """
  @behaviour Plug

  import Plug.Conn

  alias Sanbase.Utils.Config
  alias SanbaseWeb.Router.Helpers, as: Routes

  require Logger

  def init(opts), do: opts

  def call(conn, _opts), do: verify_stripe_request(conn)

  defp verify_stripe_request(conn) do
    stripe_webhook_path = Routes.stripe_path(conn, :webhook)

    case conn.request_path do
      ^stripe_webhook_path ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        do_verify(conn, body)

      _ ->
        conn
    end
  end

  defp do_verify(conn, body) do
    [signature] = get_req_header(conn, "stripe-signature")

    case Sanbase.StripeApi.Webhook.construct_event(body, signature, webhook_secret()) do
      {:ok, %Stripe.Event{}} ->
        assign(conn, :stripe_event, Jason.decode!(body))

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

  defp webhook_secret, do: Config.module_get(__MODULE__, :webhook_secret)
end
