defprotocol Sanbase.Signal do
  def send(user_trigger)
end

defimpl Sanbase.Signal, for: Any do
  require Logger

  def send(%{trigger: %{settings: %{channel: channel}}} = user_trigger) do
    max_signals_to_send = max_signals_to_send(user_trigger)

    # This will return a list of `{identifier, telegram_sent_status}` or `{:error, error}`
    # If a signal is sent to more than 1 channel this is handled properly by
    # the caller that puts the triggered identifiers in a map, so duplicates
    # disappear
    channel
    |> List.wrap()
    |> Enum.map(fn
      "telegram" -> send_telegram(user_trigger, max_signals_to_send)
      "email" -> send_email(user_trigger, max_signals_to_send)
      %{webhook: webhook_url} -> send_webhook(user_trigger, webhook_url, max_signals_to_send)
      "web_push" -> []
    end)
    |> List.flatten()
  end

  defp send_webhook(
         %{
           id: user_trigger_id,
           trigger: %{settings: %{payload: payload_map}}
         },
         webhook_url,
         max_signals_to_send
       ) do
    fun = fn identifier, payload ->
      do_send_webhook(webhook_url, identifier, payload, user_trigger_id)
    end

    send_or_limit(payload_map, max_signals_to_send, fun)
  end

  defp send_email(
         %{
           id: id,
           user: %Sanbase.Auth.User{
             email: email,
             user_settings: %{settings: %{signal_notify_email: true}}
           },
           trigger: %{settings: %{payload: payload_map}}
         },
         max_signals_to_send
       )
       when is_binary(email) and is_map(payload_map) do
    fun = fn _identifier, payload ->
      do_send_email(email, payload, id)
    end

    send_or_limit(payload_map, max_signals_to_send, fun)
  end

  defp send_email(
         %{user: %Sanbase.Auth.User{id: user_id}, trigger: %{settings: %{payload: payload_map}}},
         _max_signals_to_send
       ) do
    Logger.warn(
      "User with id #{user_id} does not have an email linked or the email notifications are disabled, so an alert cannot be sent."
    )

    Enum.map(payload_map, fn {identifier, _payload} -> {identifier, {:error, :no_email}} end)
  end

  defp send_telegram(
         %{
           id: user_trigger_id,
           user: %{user_settings: %{settings: %{telegram_chat_id: telegram_chat_id}}} = user,
           trigger: %{
             settings: %{payload: payload_map}
           }
         },
         max_signals_to_send
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 and is_map(payload_map) do
    fun = fn _identifier, payload ->
      Sanbase.Telegram.send_message(user, extend_payload(payload, user_trigger_id))
    end

    send_or_limit(payload_map, max_signals_to_send, fun)
  end

  defp send_telegram(
         %{user: %{id: id}, trigger: %{settings: %{payload: payload_map}}},
         _max_signals_to_send
       ) do
    Logger.warn("User with id #{id} does not have a telegram linked, so an alert cannot be sent.")

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, :no_telegram}}
    end)
  end

  defp extend_payload(payload, user_trigger_id) do
    """
    #{payload}
    The alert was triggered by #{SanbaseWeb.Endpoint.show_signal_url(user_trigger_id)}
    """
  end

  defp max_signals_to_send(%{user: user}) do
    user_settings = Sanbase.Auth.UserSettings.settings_for(user)

    %{
      signals_fired: signals_fired,
      signals_per_day: signals_per_day
    } = user_settings

    notifications_sent_today = Map.get(signals_fired, Date.utc_today(), 0)
    Enum.max([signals_per_day - notifications_sent_today, 0])
  end

  defp do_send_email(email, payload, trigger_id) do
    Sanbase.MandrillApi.send("signals", email, %{
      payload: extend_payload(payload, trigger_id) |> Earmark.as_html!(breaks: true)
    })
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_send_webhook(webhook_url, identifier, payload, user_trigger_id) do
    encoded_json_payload =
      %{
        timestamp: DateTime.utc_now() |> DateTime.to_unix(),
        identifier: identifier,
        content: payload,
        trigger_id: user_trigger_id,
        trigger_url: SanbaseWeb.Endpoint.show_signal_url(user_trigger_id)
      }
      |> Jason.encode!()

    case HTTPoison.post(webhook_url, encoded_json_payload, [
           {"Content-Type", "application/json"}
         ]) do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in 200..299 ->
        {identifier, :ok}

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {identifier, {:error, "Error sending webhook alert. Status code: #{code}."}}

      {:error, reason} ->
        {identifier, {:error, "Error sending webhook alert. Reason: #{inspect(reason)}"}}
    end
  end

  defp send_or_limit(payload_map, limit, fun) when is_function(fun, 2) do
    {result, _} =
      payload_map
      |> Enum.reduce({[], limit}, fn {identifier, payload}, {list, remaining} ->
        case remaining do
          0 ->
            elem = {identifier, :signals_limit_reached}
            {[elem | list], 0}

          remaining ->
            elem = {identifier, fun.(identifier, payload)}
            {[elem | list], remaining - 1}
        end
      end)

    result
  end
end
