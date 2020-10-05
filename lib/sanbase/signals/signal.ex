defprotocol Sanbase.Signal do
  def send(user_trigger)
end

defimpl Sanbase.Signal, for: Any do
  alias Sanbase.Auth.User

  @default_signals_limit_per_day Sanbase.Auth.Settings.default_signals_limit_per_day()

  @channels Map.keys(@default_signals_limit_per_day)

  def default_signals_limit_per_day(), do: @default_signals_limit_per_day

  def send(%{user: user, trigger: %{settings: %{channel: channel}}} = user_trigger) do
    # Mutex is needed, so the `max_signals_to_send` can be properly counted and
    # updated. This can happen because the sending of signals happens with a
    # concurrency of 20, so 2+ processes can be sending notifications to a user
    # at the same time and compute the same `max_signals_to_send` which would
    # lead to exceeded the given limit. Without the lock the notification for
    # exceeded the limit can be sent more than once as well.
    lock = Mutex.await(Sanbase.SignalMutex, {:user, user.id}, 30_000)

    max_signals_to_send = max_signals_to_send(user_trigger)

    # Returns a list of 2-element tuples where the first element is the channel
    # and the second element is a list of `{identifier, telegram_sent_status}` or
    # `{identifier, {:error, error}}`. If a signal is sent to more than 1 channel
    # this is handled properly by the caller that puts the triggered identifiers
    # in a map, so duplicates disappear.
    result =
      channel
      |> List.wrap()
      |> Enum.map(fn
        "telegram" ->
          {"telegram", send_telegram(user_trigger, max_signals_to_send)}

        "email" ->
          {"email", send_email(user_trigger, max_signals_to_send)}

        %{webhook: webhook_url} ->
          {"webhook", send_webhook(user_trigger, webhook_url, max_signals_to_send)}

        "web_push" ->
          {"web_push", []}
      end)

    update_user_signals_sent_per_day(user, result)
    Mutex.release(Sanbase.SignalMutex, lock)

    result |> Enum.flat_map(fn {_type, list} -> list end)
  end

  defp send_webhook(
         %{
           id: user_trigger_id,
           user: %User{} = user,
           trigger: %{settings: %{payload: payload_map}}
         },
         webhook_url,
         %{"webhook" => max_signals_to_send}
       ) do
    fun = fn identifier, payload ->
      do_send_webhook(webhook_url, identifier, payload, user_trigger_id)
    end

    send_or_limit("webhook", user, payload_map, max_signals_to_send, fun)
  end

  defp send_email(
         %{
           id: id,
           user:
             %User{
               email: email,
               user_settings: %{settings: %{signal_notify_email: true}}
             } = user,
           trigger: %{settings: %{payload: payload_map}}
         },
         %{"email" => max_signals_to_send}
       )
       when is_binary(email) and is_map(payload_map) do
    fun = fn _identifier, payload ->
      do_send_email(email, payload, id)
    end

    send_or_limit("email", user, payload_map, max_signals_to_send, fun)
  end

  defp send_email(
         %{
           user: %User{
             email: email,
             user_settings: %{settings: %{signal_notify_email: false}}
           },
           trigger: %{settings: %{payload: payload_map}}
         },
         _
       )
       when is_binary(email) and is_map(payload_map) do
    # The emails notifications are disabled
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, :channel_disabled}
    end)
  end

  defp send_email(
         %{user: %User{id: user_id}, trigger: %{settings: %{payload: payload_map}}},
         _max_signals_to_send
       ) do
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_email, user_id: user_id}}}
    end)
  end

  defp send_telegram(
         %{
           id: user_trigger_id,
           user:
             %User{
               user_settings: %{
                 settings: %{telegram_chat_id: telegram_chat_id, signal_notify_telegram: true}
               }
             } = user,
           trigger: %{
             settings: %{payload: payload_map}
           }
         },
         %{"telegram" => max_signals_to_send}
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 and is_map(payload_map) do
    fun = fn _identifier, payload ->
      Sanbase.Telegram.send_message(user, extend_payload(payload, user_trigger_id))
    end

    send_or_limit("telegram", user, payload_map, max_signals_to_send, fun)
  end

  defp send_telegram(
         %{
           user: %User{
             user_settings: %{
               settings: %{
                 telegram_chat_id: telegram_chat_id,
                 signal_notify_telegram: false
               }
             }
           },
           trigger: %{
             settings: %{payload: payload_map}
           }
         },
         _
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 and is_map(payload_map) do
    # The emails notifications are disabled
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, :channel_disabled}
    end)
  end

  defp send_telegram(
         %{user: %User{id: user_id}, trigger: %{settings: %{payload: payload_map}}},
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
    # This is done so while evaluating signals, the signals fired count is
    # properly reflected here.

    user_settings = Sanbase.Auth.UserSettings.settings_for(%Sanbase.Auth.User{id: user.id})

    %{
      signals_fired: signals_fired,
      signals_per_day_limit: signals_per_day_limit
    } = user_settings

    # A map of "channel" => list pairs
    notifications_sent_today = Map.get(signals_fired, Date.utc_today() |> to_string(), %{})

    Enum.reduce(@channels, %{}, fn channel, map ->
      channel_limit =
        Map.get(signals_per_day_limit, channel) ||
          Map.get(@default_signals_limit_per_day, channel)

      channel_sent_today = Map.get(notifications_sent_today, channel, 0)
      left_to_send = Enum.max([channel_limit - channel_sent_today, 0])

      Map.put(map, channel, left_to_send)
    end)
  end

  defp do_send_email(email, payload, trigger_id) do
    Sanbase.MandrillApi.send("signals", email, %{
      payload:
        extend_payload(payload, trigger_id)
        |> Earmark.as_html!(breaks: true, timeout: nil, mapper: &Enum.map/2)
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

  defp send_or_limit(channel, user, payload_map, limit, fun) when is_function(fun, 2) do
    {result, remaining_to_send} =
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

    if remaining_to_send == 0 and limit != 0 do
      # The limit has been reached during this call
      send_limit_reached_notification(channel, user)
    end

    result
  end

  defp update_user_signals_sent_per_day(user, sent_list_per_channel) do
    %{signals_fired: signals_fired} =
      Sanbase.Auth.UserSettings.settings_for(%Sanbase.Auth.User{id: user.id})

    map_key = Date.utc_today() |> to_string()

    signals_fired_now =
      Enum.into(sent_list_per_channel, %{}, fn {channel, sent_list} ->
        count = Enum.count(sent_list, fn {_, result} -> result == :ok end)
        {channel, count}
      end)

    signals_fired_today = Map.get(signals_fired, map_key, %{})

    signals_fired_today_updated =
      Enum.into(@channels, %{}, fn channel ->
        count = Map.get(signals_fired_today, channel, 0) + Map.get(signals_fired_now, channel, 0)

        {channel, count}
      end)

    signals_fired = Map.put(signals_fired, map_key, signals_fired_today_updated)

    Sanbase.Auth.UserSettings.update_settings(user, %{signals_fired: signals_fired})
  end

  defp send_limit_reached_notification("telegram", user) do
    Sanbase.Telegram.send_message(
      user,
      limit_reached_payload("telegram")
    )
  end

  defp send_limit_reached_notification("email", user) do
    Sanbase.MandrillApi.send("signals", user.email, %{
      payload: limit_reached_payload("email") |> Earmark.as_html!(breaks: true)
    })
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp send_limit_reached_notification(_channel), do: :ok

  defp limit_reached_payload(channel) do
    """
    Your maximum amount of #{channel} alert notifications per day has been reached.

    To see a full list of triggered signals today, please visit your [Sanbase Feed](#{
      SanbaseWeb.Endpoint.feed_url()
    }).

    If you’d like to raise your daily notification limit, you can do so anytime in your [Sanbase Account Settings](#{
      SanbaseWeb.Endpoint.user_account_url()
    }).
    """
  end
end
