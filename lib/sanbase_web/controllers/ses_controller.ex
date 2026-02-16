defmodule SanbaseWeb.SESController do
  use SanbaseWeb, :controller

  require Logger

  alias Sanbase.Email.SesEmailEvent

  def webhook(conn, %{"secret" => secret} = params) do
    expected_secret = Application.get_env(:sanbase, SanbaseWeb.SESController)[:webhook_secret]

    if is_binary(expected_secret) and Plug.Crypto.secure_compare(secret, expected_secret) do
      handle_sns_message(params)
      send_resp(conn, 200, "")
    else
      Logger.warning("Invalid SES webhook secret")
      send_resp(conn, 403, "Forbidden")
    end
  end

  defp handle_sns_message(%{"Type" => "SubscriptionConfirmation", "SubscribeURL" => url}) do
    Logger.info("Confirming SNS subscription")

    case Req.get(url) do
      {:ok, %{status: 200}} ->
        Logger.info("SNS subscription confirmed")

      {:ok, %{status: status}} ->
        Logger.error("SNS subscription confirmation failed with status: #{status}")

      {:error, reason} ->
        Logger.error("Failed to confirm SNS subscription: #{inspect(reason)}")
    end
  end

  defp handle_sns_message(%{"Type" => "Notification", "Message" => message_json})
       when is_binary(message_json) do
    case Jason.decode(message_json) do
      {:ok, ses_event} ->
        handle_ses_event(ses_event)

      {:error, reason} ->
        Logger.error("Failed to parse SES event JSON: #{inspect(reason)}")
    end
  end

  defp handle_sns_message(%{"Type" => "Notification", "Message" => %{} = ses_event}) do
    handle_ses_event(ses_event)
  end

  defp handle_sns_message(message) do
    Logger.warning("Unknown SNS message type: #{inspect(Map.get(message, "Type", "missing"))}")
  end

  defp handle_ses_event(%{"eventType" => "Bounce", "bounce" => bounce, "mail" => mail}) do
    Enum.each(List.wrap(bounce["bouncedRecipients"]), fn recipient ->
      create_event(%{
        message_id: mail["messageId"],
        email: recipient["emailAddress"],
        event_type: "Bounce",
        bounce_type: bounce["bounceType"],
        bounce_sub_type: bounce["bounceSubType"],
        timestamp: parse_timestamp(bounce["timestamp"]),
        raw_data: %{"bounce" => bounce, "mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{"eventType" => "Complaint", "complaint" => complaint, "mail" => mail}) do
    Enum.each(List.wrap(complaint["complainedRecipients"]), fn recipient ->
      create_event(%{
        message_id: mail["messageId"],
        email: recipient["emailAddress"],
        event_type: "Complaint",
        complaint_feedback_type: complaint["complaintFeedbackType"],
        timestamp: parse_timestamp(complaint["timestamp"]),
        raw_data: %{"complaint" => complaint, "mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{"eventType" => "Delivery", "delivery" => delivery, "mail" => mail}) do
    Enum.each(List.wrap(delivery["recipients"]), fn email ->
      create_event(%{
        message_id: mail["messageId"],
        email: email,
        event_type: "Delivery",
        smtp_response: delivery["smtpResponse"],
        timestamp: parse_timestamp(delivery["timestamp"]),
        raw_data: %{"delivery" => delivery, "mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{"eventType" => "Send", "mail" => mail}) do
    Enum.each(List.wrap(mail["destination"]), fn email ->
      create_event(%{
        message_id: mail["messageId"],
        email: email,
        event_type: "Send",
        timestamp: parse_timestamp(mail["timestamp"]),
        raw_data: %{"mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{"eventType" => "Reject", "reject" => reject, "mail" => mail}) do
    Enum.each(List.wrap(mail["destination"]), fn email ->
      create_event(%{
        message_id: mail["messageId"],
        email: email,
        event_type: "Reject",
        reject_reason: reject["reason"],
        timestamp: parse_timestamp(mail["timestamp"]),
        raw_data: %{"reject" => reject, "mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{
         "eventType" => "DeliveryDelay",
         "deliveryDelay" => delay,
         "mail" => mail
       }) do
    Enum.each(List.wrap(delay["delayedRecipients"]), fn recipient ->
      create_event(%{
        message_id: mail["messageId"],
        email: recipient["emailAddress"],
        event_type: "DeliveryDelay",
        delay_type: delay["delayType"],
        timestamp: parse_timestamp(delay["timestamp"]),
        raw_data: %{"deliveryDelay" => delay, "mail" => mail}
      })
    end)
  end

  defp handle_ses_event(%{"eventType" => event_type}) do
    Logger.warning("Unhandled SES event type: #{event_type}")
  end

  defp create_event(attrs) do
    case SesEmailEvent.create(attrs) do
      {:ok, %{id: nil}} ->
        Logger.debug(
          "Duplicate SES #{attrs.event_type} ignored for message_id: #{attrs.message_id}"
        )

      {:ok, _event} ->
        Logger.info("SES #{attrs.event_type} recorded for message_id: #{attrs.message_id}")

      {:error, changeset} ->
        Logger.error(
          "Failed to record SES event for message_id #{attrs.message_id}: #{inspect(changeset.errors)}"
        )
    end
  end

  defp parse_timestamp(timestamp_string) when is_binary(timestamp_string) do
    case DateTime.from_iso8601(timestamp_string) do
      {:ok, datetime, _} -> datetime
      {:error, _} -> DateTime.utc_now()
    end
  end

  defp parse_timestamp(_), do: DateTime.utc_now()
end
