defprotocol Sanbase.Signal do
  def send(user_trigger)
end

defimpl Sanbase.Signal, for: Any do
  def send(%{user: user, trigger: %{settings: %{channel: channel}}} = user_trigger) do
    # Mutex is needed, so the `max_signals_to_send` can be properly counted and
    # updated. This can happen because the sending of signals happens with a
    # concurrency of 20, so 2+ processes can be sending notifications to a user
    # at the same time and compute the same `max_signals_to_send` which would
    # lead to exceeded the given limit. Without the lock the notification for
    # exceeded the limit can be sent more than once as well.
    lock = Mutex.await(Sanbase.SignalMutex, {:user, user.id}, 30_000)

    max_signals_to_send = max_signals_to_send(user_trigger)

    # This will return a list of `{identifier, telegram_sent_status}` or
    # `{identifier, {:error, error}}`. If a signal is sent to more than 1 channel
    # this is handled properly by the caller that puts the triggered identifiers
    # in a map, so duplicates disappear.
    result =
      channel
      |> List.wrap()
      |> Enum.map(fn
        "telegram" -> send_telegram(user_trigger, max_signals_to_send)
        "email" -> send_email(user_trigger, max_signals_to_send)
        %{webhook: webhook_url} -> send_webhook(user_trigger, webhook_url, max_signals_to_send)
        "web_push" -> []
      end)
      |> List.flatten()

    update_user_signals_sent_per_day(user, result)
    Mutex.release(Sanbase.SignalMutex, lock)

    result
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
         %{user: %{id: user_id}, trigger: %{settings: %{payload: payload_map}}},
         _max_signals_to_send
       ) do
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_email, user_id: user_id}}}
    end)
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
         %{user: %{id: user_id}, trigger: %{settings: %{payload: payload_map}}},
         _max_signals_to_send
       ) do
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_telegram, user_id: user_id}}}
    end)
  end

  defp extend_payload(payload, user_trigger_id) do
    """
    #{payload}
    The alert was triggered by #{SanbaseWeb.Endpoint.show_signal_url(user_trigger_id)}
    """
  end

  defp max_signals_to_send(%{user: user}) do
    # Force the settings to be fetched and not taken from the user struct
    # This is done so while evaluating signals, the signals fired will be properly
    # updated
    user_settings = Sanbase.Auth.UserSettings.settings_for(%Sanbase.Auth.User{id: user.id})

    %{
      signals_fired: signals_fired,
      signals_per_day: signals_per_day
    } = user_settings

    notifications_sent_today = Map.get(signals_fired, Date.utc_today() |> to_string(), 0)
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

  defp update_user_signals_sent_per_day(user, sent_list) do
    %{signals_fired: signals_fired, signals_per_day: signals_per_day} =
      Sanbase.Auth.UserSettings.settings_for(%Sanbase.Auth.User{id: user.id})

    map_key = Date.utc_today() |> to_string()
    count = Enum.count(sent_list, fn {_, result} -> result == :ok end)
    signals_fired_today = Map.get(signals_fired, map_key, 0)

    # If this trigger is the one that went over the allowed signals per day
    # send a message to the user. Only one such notification per day should be sent
    # TODO: Rework by finding all channels used by the user and sending the notificaiton
    # to them - it could be only telegram, only email or both.
    case signals_fired_today < signals_per_day and signals_fired_today + count >= signals_per_day do
      false ->
        :ok

      true ->
        Sanbase.Telegram.send_message(
          user,
          """
          The allowed number of signal notifications per day has been reached.
          To see the full list of fired signals, please check your [feed on Sanbase](#{
            SanbaseWeb.Endpoint.feed_url()
          }).
          If you want to receive more notifications per day, please visit your
          [account settings on Sanbase](#{SanbaseWeb.Endpoint.user_account_url()})
          """
        )
    end

    signals_fired = Map.put(signals_fired, map_key, count + signals_fired_today)

    Sanbase.Auth.UserSettings.update_settings(user, %{signals_fired: signals_fired})
  end
end
