defprotocol Sanbase.Alert do
  def send(user_trigger)
end

defimpl Sanbase.Alert, for: Any do
  alias Sanbase.Accounts.{UserSettings, Settings, User}

  require Logger
  require Sanbase.Utils.Config, as: Config

  @default_alerts_limit_per_day Settings.default_alerts_limit_per_day()

  @channels Map.keys(@default_alerts_limit_per_day)

  def default_alerts_limit_per_day(), do: @default_alerts_limit_per_day

  @doc ~s"""
  Send a triggered alert to the configured notification channels.

  It is important that this function is called either alone, without any other `send`
  running for the same user, or it is called from the `Sanbase.Alert.Scheduler` module
  which takes care of running concurrently only the triggers that are safe to run
  in parallel.
  """
  def send(%{user: user, trigger: %{settings: %{channel: channel}}} = user_trigger) do
    {:ok, max_alerts_to_send} = UserSettings.max_alerts_to_send(user_trigger.user)

    # Returns a list of 2-element tuples where the first element is the channel
    # and the second element is a list of `{identifier, telegram_sent_status}` or
    # `{identifier, {:error, error}}`. If an alert is sent to more than 1 channel
    # this is handled properly by the caller that puts the triggered identifiers
    # in a map, so duplicates disappear.

    result =
      channel
      |> List.wrap()
      |> Enum.map(&send_to_channel(&1, user_trigger, max_alerts_to_send))

    update_user_alerts_sent_per_day(user, result)

    Enum.flat_map(result, fn {_type, list} -> list end)
  end

  defp send_to_channel("telegram", user_trigger, max_alerts_to_send),
    do: {"telegram", send_telegram(user_trigger, max_alerts_to_send)}

  defp send_to_channel("email", user_trigger, max_alerts_to_send),
    do: {"email", send_email(user_trigger, max_alerts_to_send)}

  defp send_to_channel(%{webhook: webhook_url}, user_trigger, max_alerts_to_send),
    do: {"webhook", send_webhook(user_trigger, webhook_url, max_alerts_to_send)}

  defp send_to_channel(%{telegram_channel: channel}, user_trigger, max_alerts_to_send),
    do: {"telegram_channel", send_telegram_channel(user_trigger, channel, max_alerts_to_send)}

  defp send_to_channel("web_push", _user_trigger, _max_alerts_to_send), do: {"web_push", []}

  defp send_webhook(
         trigger,
         webhook_url,
         %{"webhook" => max_alerts_to_send}
       ) do
    %{id: user_trigger_id} = trigger

    fun = fn identifier, payload ->
      case Sanbase.Validation.valid_url?(webhook_url) do
        :ok ->
          payload = transform_payload(payload, trigger.id, :webhook)
          do_send_webhook(webhook_url, identifier, payload, user_trigger_id)

        {:error, reason} ->
          {:error, %{reason: :webhook_url_not_valid, error: reason}}
      end
    end

    send_or_limit("webhook", trigger, max_alerts_to_send, fun)
  end

  defp send_email(
         %{
           user:
             %User{
               email: email,
               user_settings: %{settings: %{alert_notify_email: true}}
             } = user
         } = trigger,
         %{"email" => max_alerts_to_send}
       )
       when is_binary(email) do
    fun = fn _identifier, payload ->
      payload = transform_payload(payload, trigger.id, :email)
      do_send_email(user, payload)
    end

    send_or_limit("email", trigger, max_alerts_to_send, fun)
  end

  defp send_email(
         %{
           user: %User{
             email: email,
             user_settings: %{settings: %{alert_notify_email: false}}
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
       {:error,
        %{reason: :email_alert_notifications_disabled, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_email(trigger, _max_alerts_to_send) do
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
                 alert_notify_telegram: true
               }
             }
           }
         } = trigger,
         %{"telegram" => max_alerts_to_send}
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 do
    fun = fn _identifier, payload ->
      payload = transform_payload(payload, trigger.id, :telegram)

      Sanbase.Telegram.send_message(trigger.user, payload)
      |> maybe_transform_telegram_response(trigger)
    end

    send_or_limit("telegram", trigger, max_alerts_to_send, fun)
  end

  defp send_telegram(
         %{
           user: %User{
             user_settings: %{
               settings: %{
                 telegram_chat_id: telegram_chat_id,
                 alert_notify_telegram: false
               }
             }
           }
         } = trigger,
         _max_alerts_to_send
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
       {:error,
        %{
          reason: :telegram_alert_notifications_disabled,
          user_id: user_id,
          trigger_id: trigger_id
        }}}
    end)
  end

  defp send_telegram(trigger, _max_alerts_to_send) do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{settings: %{payload: payload_map}}
    } = trigger

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_telegram, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_telegram_channel(
         trigger,
         channel,
         %{"telegram_channel" => max_alerts_to_send}
       ) do
    fun = fn _identifier, payload ->
      payload = transform_payload(payload, trigger.id, :telegram_channel)

      Sanbase.Telegram.send_message_to_chat_id(channel, payload)
      |> maybe_transform_telegram_response(trigger)
    end

    send_or_limit("telegram_channel", trigger, max_alerts_to_send, fun)
  end

  defp maybe_transform_telegram_response({:error, error}, trigger) do
    case String.contains?(error, "blocked the telegram bot") do
      true ->
        # In case the trigger does not have other channels but only telegram
        # and the user has blocked our telegram bot, the alert is disabled
        # so it does not spend resources running
        deactivate_if_telegram_channel_only(trigger)

        %{user: %User{id: user_id}, trigger: %{id: trigger_id}} = trigger
        {:error, %{reason: :telegram_bot_blocked, user_id: user_id, trigger_id: trigger_id}}

      false ->
        {:error, error}
    end
  end

  defp maybe_transform_telegram_response(response, _trigger), do: response

  defp deactivate_if_telegram_channel_only(trigger) do
    case trigger do
      %{trigger: %{settings: %{channel: channel}}} when channel in ["telegram", ["telegram"]] ->
        Logger.info("Deactivating user trigger with id #{trigger.id} because the user \
        with id #{trigger.user.id} has blocked the telegram bot.")
        Sanbase.Alert.UserTrigger.update_is_active(trigger.id, trigger.user, false)

      _ ->
        :ok
    end
  end

  defp transform_payload(payload, user_trigger_id, channel) do
    payload
    |> maybe_add_stage_tag(user_trigger_id, channel)
    |> maybe_add_alert_link(user_trigger_id, channel)
    |> String.replace("\n\n\n", "\n\n")
  end

  defp maybe_add_stage_tag(payload, _id, _channel) do
    case Config.module_get(Sanbase, :deployment_env) do
      "stage" -> "[STAGE]" <> payload
      _ -> payload
    end
  end

  defp maybe_add_alert_link(payload, user_trigger_id, :telegram) do
    """
    #{payload}
    [View Alert](#{SanbaseWeb.Endpoint.show_alert_url(user_trigger_id)})
    """
  end

  defp maybe_add_alert_link(payload, user_trigger_id, :email) do
    """
    #{payload}
    Triggered by #{SanbaseWeb.Endpoint.show_alert_url(user_trigger_id)}
    """
  end

  defp maybe_add_alert_link(payload, _, :webhook), do: payload
  defp maybe_add_alert_link(payload, _trigger_id, :telegram_channel), do: payload

  defp do_send_email(user, payload) do
    payload_html = Earmark.as_html!(payload, breaks: true, timeout: nil, mapper: &Enum.map/2)
    name = Sanbase.Accounts.User.get_name(user)

    Sanbase.TemplateMailer.send(user.email, Sanbase.Email.Template.alerts_template(), %{
      name: name,
      username: name,
      payload: payload_html
    })
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  def do_send_webhook(
        "https://hooks.slack.com/services" <> _rest = webhook_url,
        _identifier,
        payload,
        trigger_id
      ) do
    encoded_json_payload = Jason.encode!(%{text: payload})

    HTTPoison.post(webhook_url, encoded_json_payload, [{"Content-Type", "application/json"}])
    |> handle_webhook_response(trigger_id)
  end

  def do_send_webhook(webhook_url, identifier, payload, trigger_id) do
    encoded_json_payload =
      %{
        timestamp: DateTime.utc_now() |> DateTime.to_unix(),
        identifier: identifier,
        content: payload,
        trigger_id: trigger_id,
        trigger_url: SanbaseWeb.Endpoint.show_alert_url(trigger_id)
      }
      |> Jason.encode!()

    HTTPoison.post(webhook_url, encoded_json_payload, [{"Content-Type", "application/json"}])
    |> handle_webhook_response(trigger_id)
  end

  defp handle_webhook_response(response, trigger_id) do
    case response do
      {:ok, %HTTPoison.Response{status_code: status_code}} when status_code in 200..299 ->
        :ok

      {:ok, %HTTPoison.Response{status_code: code}} ->
        {:error, %{reason: :webhook_send_fail, status_code: code, trigger_id: trigger_id}}

      {:error, error} ->
        {:error, %{reason: :webhook_send_fail, error: error, trigger_id: trigger_id}}
    end
  end

  defp send_or_limit(channel, trigger, limit, send_alert_fun)
       when is_function(send_alert_fun, 2) do
    %{
      user: user,
      trigger: %{settings: %{payload: payload_map}}
    } = trigger

    {result, remaining_to_send} =
      payload_map
      |> Enum.reduce({[], limit}, fn
        {identifier, _payload}, {list, 0 = _remaining} ->
          elem = {identifier, limits_reached_error_tuple(user, trigger, channel)}
          {[elem | list], _remaining = 0}

        {identifier, payload}, {list, remaining} ->
          elem = {identifier, send_alert_fun.(identifier, payload)}
          {[elem | list], remaining - 1}
      end)

    if remaining_to_send == 0 and limit != 0 do
      # The limit has been reached during this call
      send_limit_reached_notification(channel, user)
    end

    result
  end

  defp limits_reached_error_tuple(user, trigger, channel) do
    {:error,
     %{reason: :alerts_limit_reached, user_id: user.id, trigger_id: trigger.id, channel: channel}}
  end

  defp update_user_alerts_sent_per_day(user, sent_list_per_channel) do
    %{alerts_fired: alerts_fired} = Sanbase.Accounts.UserSettings.settings_for(user, force: true)

    map_key = Date.utc_today() |> to_string()

    alerts_fired_now =
      Enum.into(sent_list_per_channel, %{}, fn {channel, sent_list} ->
        count = Enum.count(sent_list, fn {_, result} -> result == :ok end)
        {channel, count}
      end)

    alerts_fired_today = Map.get(alerts_fired, map_key, %{})

    alerts_fired_today_updated =
      Enum.into(@channels, %{}, fn channel ->
        count = Map.get(alerts_fired_today, channel, 0) + Map.get(alerts_fired_now, channel, 0)

        {channel, count}
      end)

    alerts_fired = Map.put(alerts_fired, map_key, alerts_fired_today_updated)

    Sanbase.Accounts.UserSettings.update_settings(user, %{alerts_fired: alerts_fired})
  end

  defp send_limit_reached_notification("telegram", user) do
    Sanbase.Telegram.send_message(
      user,
      limit_reached_payload("telegram")
    )
  end

  defp send_limit_reached_notification("email", user) do
    payload_html =
      limit_reached_payload("email")
      |> Earmark.as_html!(breaks: true, timeout: nil, mapper: &Enum.map/2)

    name = Sanbase.Accounts.User.get_name(user)

    Sanbase.TemplateMailer.send(user.email, Sanbase.Email.Template.alerts_template(), %{
      name: name,
      username: name,
      payload: payload_html
    })
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, %{reason: :email_send_fail, error: reason}}
    end
  end

  defp send_limit_reached_notification(_channel, _user), do: :ok

  defp limit_reached_payload(channel) do
    """
    Your maximum amount of #{channel} alert notifications per day has been reached.

    To see the full list of triggered alerts today, please visit your [Sanbase Feed](#{SanbaseWeb.Endpoint.feed_url()}).

    If you’d like to raise your daily notification limit, you can do so anytime in your [Sanbase Account Settings](#{SanbaseWeb.Endpoint.user_account_url()}).
    """
  end
end
