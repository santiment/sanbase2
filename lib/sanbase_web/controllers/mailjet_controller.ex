defmodule SanbaseWeb.MailjetController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Email.MailjetEventHandler

  def webhook(conn, %{"secret" => secret} = params) do
    expected_secret = webhook_secret()

    if is_binary(expected_secret) and Plug.Crypto.secure_compare(secret, expected_secret) do
      handle_webhook(conn, Map.delete(params, "secret"))
    else
      Logger.warning("Invalid Mailjet webhook secret")

      conn
      |> send_resp(403, "Forbidden")
      |> halt()
    end
  end

  def webhook(conn, _params) do
    conn
    |> send_resp(403, "Forbidden")
    |> halt()
  end

  defp handle_webhook(conn, params) do
    Logger.info("Received Mailjet webhook event: #{Map.get(params, "event")}")

    with "unsub" <- Map.get(params, "event"),
         email when is_binary(email) <- Map.get(params, "email"),
         list_id when not is_nil(list_id) <- Map.get(params, "mj_list_id") do
      Logger.info("Processing unsubscribe event for email: #{email}, list_id: #{list_id}")

      case MailjetEventHandler.handle_unsubscribe(email, list_id) do
        {:ok, _} ->
          Logger.info("Successfully processed unsubscribe for #{email}")

        {:error, reason} ->
          Logger.warning("Failed to process unsubscribe for #{email}: #{inspect(reason)}")
      end
    else
      nil ->
        Logger.warning(
          "Missing required parameters in Mailjet webhook event: #{Map.get(params, "event")}"
        )

      unexpected ->
        Logger.warning("Unexpected data in Mailjet webhook: #{inspect(unexpected)}")
    end

    # Always respond with 200 to acknowledge receipt of webhook
    send_resp(conn, 200, "")
  end

  defp webhook_secret do
    Application.get_env(:sanbase, __MODULE__)[:webhook_secret]
  end
end
