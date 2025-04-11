defmodule SanbaseWeb.MailjetController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Email.MailjetEventHandler

  def webhook(conn, params) do
    Logger.info("Received Mailjet webhook: #{inspect(params)}")

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
        Logger.warning("Missing required parameters in Mailjet webhook: #{inspect(params)}")

      unexpected ->
        Logger.warning("Unexpected data in Mailjet webhook: #{inspect(unexpected)}")
    end

    # Always respond with 200 to acknowledge receipt of webhook
    send_resp(conn, 200, "")
  end
end
