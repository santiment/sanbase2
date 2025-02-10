defmodule SanbaseWeb.StripeController do
  use SanbaseWeb, :controller

  alias Sanbase.Billing.StripeEvent

  require Logger

  def webhook(conn, _params) do
    stripe_event = conn.assigns[:stripe_event]
    Logger.info("Stripe event received: #{inspect(stripe_event)}")

    case StripeEvent.by_id(stripe_event["id"]) do
      nil ->
        case StripeEvent.create(stripe_event) do
          {:ok, _} ->
            # spawn a separate process to handle the event and return immediately
            StripeEvent.handle_event_async(stripe_event)
            success_response(conn)

          {:error, _} ->
            error_response(conn)
        end

      # duplicate event - return 200
      _ ->
        success_response(conn)
    end
  end

  defp success_response(conn) do
    conn
    |> resp(200, "OK")
    |> send_resp()
  end

  defp error_response(conn) do
    conn
    |> resp(500, "Error")
    |> send_resp()
  end
end
