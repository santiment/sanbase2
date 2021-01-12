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
         trigger,
         webhook_url,
         %{"webhook" => max_signals_to_send}
       ) do
    %{id: user_trigger_id} = trigger

    fun = fn identifier, payload ->
      do_send_webhook(webhook_url, identifier, payload, user_trigger_id)
    end

    send_or_limit("webhook", trigger, max_signals_to_send, fun)
  end

  defp send_email(
         %{
           user: %User{
             email: email,
             user_settings: %{settings: %{signal_notify_email: true}}
           }
         } = trigger,
         %{"email" => max_signals_to_send}
       )
       when is_binary(email) do
    fun = fn _identifier, payload ->
      do_send_email(email, payload, trigger.id)
    end

    send_or_limit("email", trigger, max_signals_to_send, fun)
  end

  defp send_email(
         %{
           user: %User{
             email: email,
             user_settings: %{settings: %{signal_notify_email: false}}
           }
         } = trigger,
         _
       )
       when is_binary(email) do
    %{id: trigger_id, user: %{id: user_id}, trigger: %{settings: %{payload: payload_map}}} =
      trigger

    # The emails notifications are disabled
    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier,
       {:error, %{reason: :email_channel_disabled, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_email(trigger, _max_signals_to_send) do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{settings: %{payload: payload_map}}
    } = trigger

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_email, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_telegram(
         %{
           user: %User{
             user_settings: %{
               settings: %{
                 telegram_chat_id: telegram_chat_id,
                 signal_notify_telegram: true
               }
             }
           }
         } = trigger,
         %{"telegram" => max_signals_to_send}
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 do
    fun = fn _identifier, payload ->
      Sanbase.Telegram.send_message(trigger.user, extend_payload(payload, trigger.id))
      |> maybe_transform_telegram_response(trigger)
    end

    send_or_limit("telegram", trigger, max_signals_to_send, fun)
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
           }
         } = trigger,
         _
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{
        settings: %{payload: payload_map}
      }
    } = trigger

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier,
       {:error, %{reason: :telegram_channel_disabled, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_telegram(trigger, _max_signals_to_send) do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{settings: %{payload: payload_map}}
    } = trigger

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_telegram, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp maybe_transform_telegram_response({:error, error}, trigger) do
    %{user: %User{id: user_id}, trigger: %{id: trigger_id}} = trigger

    case is_binary(error) and String.contains?(error, "blocked the telegram bot") do
      true -> {:error, %{reason: :telegram_bot_blocked, user_id: user_id, trigger_id: trigger_id}}
      false -> {:error, error}
    end
  end

  defp maybe_transform_telegram_response(response, _trigger), do: response

  defp extend_payload(payload, user_trigger_id) do
    """
    #{payload}
    Triggered by #{SanbaseWeb.Endpoint.show_signal_url(user_trigger_id)}
    """
  end

  defp max_signals_to_send(%{user: user}) do
    # Force the settings to be fetched and not taken from the user struct
    # This is done so while evaluating signals, the signals fired count is
    # properly reflected here.
    user_settings = Sanbase.Auth.UserSettings.settings_for(user, force: true)

    %{
      signals_fired: signals_fired,
      signals_per_day_limit: signals_per_day_limit
    } = user_settings

    # A map of "channel" => list pairs
    notifications_sent_today = Map.get(signals_fired, Date.utc_today() |> to_string(), %{})

    Enum.reduce(@channels, %{}, fn channel, map ->
      channel_limit =
        (Map.get(signals_per_day_limit, channel) ||
           Map.get(@default_signals_limit_per_day, channel))
        |> Sanbase.Math.to_integer()

      channel_sent_today =
        Map.get(notifications_sent_today, channel, 0)
        |> Sanbase.Math.to_integer()

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

  def do_send_webhook(
        "https://hooks.slack.com/services" <> _rest = webhook_url,
        identifier,
        payload,
        trigger_id
      ) do
    encoded_json_payload =
      %{
        text: payload
      }
      |> Jason.encode!()

    HTTPoison.post(webhook_url, encoded_json_payload, [{"Content-Type", "application/json"}])
    |> handle_webhook_response(identifier, trigger_id)
  end

  def do_send_webhook(webhook_url, identifier, payload, trigger_id) do
    encoded_json_payload =
      %{
        timestamp: DateTime.utc_now() |> DateTime.to_unix(),
        identifier: identifier,
        content: payload,
        trigger_id: trigger_id,
        trigger_url: SanbaseWeb.Endpoint.show_signal_url(trigger_id)
      }
      |> Jason.encode!()

    HTTPoison.post(webhook_url, encoded_json_payload, [{"Content-Type", "application/json"}])
    |> handle_webhook_response(identifier, trigger_id)
  end

  defp handle_webhook_response(response, identifier, trigger_id) do
    case response do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in 200..299 ->
        {identifier, :ok}

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {identifier,
         {:error, %{reason: :webhook_send_fail, status_code: code, trigger_id: trigger_id}}}

      {:error, error} ->
        {identifier,
         {:error, %{reason: :webhook_send_fail, error: error, trigger_id: trigger_id}}}
    end
  end

  defp send_or_limit(channel, trigger, limit, fun) when is_function(fun, 2) do
    %{
      id: trigger_id,
      user: user,
      trigger: %{
        settings: %{payload: payload_map}
      }
    } = trigger

    signals_limit_reached_error =
      {:error, %{reason: :signals_limit_reached, user_id: user.id, trigger_id: trigger_id}}

    {result, remaining_to_send} =
      payload_map
      |> Enum.reduce({[], limit}, fn {identifier, payload}, {list, remaining} ->
        case remaining do
          0 ->
            {[{identifier, signals_limit_reached_error} | list], 0}

          remaining ->
            {[{identifier, fun.(identifier, payload)} | list], remaining - 1}
        end
      end)

    if remaining_to_send == 0 and limit != 0 do
      # The limit has been reached during this call
      send_limit_reached_notification(channel, user)
    end

    result
  end

  defp update_user_signals_sent_per_day(user, sent_list_per_channel) do
    %{signals_fired: signals_fired} = Sanbase.Auth.UserSettings.settings_for(user, force: true)

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
      {:error, reason} -> {:error, %{reason: :email_send_fail, error: reason}}
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
