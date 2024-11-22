defprotocol Sanbase.Alert do
  def send(user_trigger)
end

defimpl Sanbase.Alert, for: Any do
  alias Sanbase.Accounts.{UserSettings, Settings, User}
  alias Sanbase.Utils.Config

  require Logger

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
         } = user_trigger,
         %{"telegram" => max_alerts_to_send}
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 do
    fun = fn _identifier, payload ->
      payload = transform_payload(payload, user_trigger.id, :telegram)

      response = Sanbase.Telegram.send_message(user_trigger.user, payload)

      # Deactivate the alert if the message is sent to telegram, telegram
      # is the only channel and the telegram bot is blocked by the user.
      # The function returns :ok or {:error, reason} which is used in the
      # caller.
      deactivate_alert_if_bot_blocked(response, user_trigger)
    end

    send_or_limit("telegram", user_trigger, max_alerts_to_send, fun)
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
         } = user_trigger,
         _max_alerts_to_send
       )
       when is_integer(telegram_chat_id) and telegram_chat_id > 0 do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{
        settings: %{payload: payload_map}
      }
    } = user_trigger

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

  defp send_telegram(user_trigger, _max_alerts_to_send) do
    %{
      id: trigger_id,
      user: %User{id: user_id},
      trigger: %{settings: %{payload: payload_map}}
    } = user_trigger

    Enum.map(payload_map, fn {identifier, _payload} ->
      {identifier, {:error, %{reason: :no_telegram, user_id: user_id, trigger_id: trigger_id}}}
    end)
  end

  defp send_telegram_channel(
         user_trigger,
         channel,
         %{"telegram_channel" => max_alerts_to_send}
       ) do
    fun = fn _identifier, payload ->
      payload = transform_payload(payload, user_trigger.id, :telegram_channel)
      {payload, opts} = maybe_extend_payload_telegram_channel(payload, user_trigger, channel)

      response = Sanbase.Telegram.send_message_to_chat_id(channel, payload)
      # Send a reply to the original message, if it was delived successfuly
      # It contains the chat preview image.
      maybe_send_preview_image_as_reply(response, user_trigger, channel, opts)
      # Deactivate the alert if the message is sent to telegram, telegram
      # is the only channel and the telegram bot is blocked by the user.
      # The function returns :ok or {:error, reason} which is used in the
      # caller.
      deactivate_alert_if_bot_blocked(response, user_trigger)
    end

    send_or_limit("telegram_channel", user_trigger, max_alerts_to_send, fun)
  end

  # For daily and intraday metric signals add preview image of the chart for metric + asset
  # The preview image should be a reply to the original alert message
  # only for Sanr signals telegram channel and one test channel
  defp maybe_send_preview_image_as_reply(
         {:ok, response},
         %{trigger: %{settings: %{type: type}}},
         channel,
         opts
       )
       when type in ["metric_signal", "daily_metric_signal"] and
              channel in ["@test_san_bot86", "@sanr_signals"] do
    if short_url_id = Keyword.get(opts, :short_url_id) do
      send_preview_image(response, channel, short_url_id)
    end
  end

  defp maybe_send_preview_image_as_reply(_, _, _, _), do: :ok

  defp deactivate_alert_if_bot_blocked({:error, error}, user_trigger) do
    case String.contains?(error, "blocked the telegram bot") do
      true ->
        # In case the user_trigger does not have other channels but only telegram
        # and the user has blocked our telegram bot, the alert is disabled
        # so it does not spend resources running
        deactivate_if_telegram_channel_only(user_trigger)

        %{user: %User{id: user_id}, trigger: %{id: trigger_id}} = user_trigger
        {:error, %{reason: :telegram_bot_blocked, user_id: user_id, trigger_id: trigger_id}}

      false ->
        {:error, error}
    end
  end

  defp deactivate_alert_if_bot_blocked(_response, _trigger), do: :ok

  defp send_preview_image(response, channel, short_url_id) do
    Task.Supervisor.async_nolink(Sanbase.TaskSupervisor, fn ->
      reply_to_message_id = Jason.decode!(response)["result"]["message_id"]

      image_url = "#{preview_url()}/chart/#{short_url_id}"

      HTTPoison.get(image_url, [basic_auth_header()], timeout: 15_000, recv_timeout: 15_000)
      |> handle_chart_preview_response(channel, reply_to_message_id, image_url)
    end)
  end

  defp handle_chart_preview_response({:error, error}, _channel, _reply_to_message_id, image_url) do
    Logger.error("Failed to fetch chart preview image for #{image_url}: #{inspect(error)}")
  end

  defp handle_chart_preview_response({:ok, response}, channel, reply_to_message_id, image_url) do
    content_type = response.headers |> Enum.into(%{}) |> Map.get("Content-Type")

    case content_type do
      "image/jpeg" ->
        Sanbase.Telegram.send_photo_by_file_content(
          channel,
          response.body,
          reply_to_message_id
        )

      content_type ->
        Logger.error(
          "Response of #{image_url} was expected to be with content type image/jpg, got #{content_type} instead"
        )
    end
  end

  defp deactivate_if_telegram_channel_only(user_trigger) do
    case user_trigger do
      %{trigger: %{settings: %{channel: channel}}} when channel in ["telegram", ["telegram"]] ->
        Logger.info("Deactivating user trigger with id #{user_trigger.id} because the user \
        with id #{user_trigger.user.id} has blocked the telegram bot.")
        Sanbase.Alert.UserTrigger.update_is_active(user_trigger.id, user_trigger.user_id, false)

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

  # extend Sanr signals telegram channel and one test channel
  # when the alert is defined on a metric
  defp maybe_extend_payload_telegram_channel(
         payload,
         %{trigger: %{settings: %{metric: metric} = settings}} = user_trigger,
         channel
       )
       when channel in ["@test_san_bot86", "@sanr_signals"] do
    template_kv = settings.template_kv || %{}
    slugs = Map.keys(template_kv)

    Logger.info(
      "[maybe_extend_payload_telegram_channel_#{user_trigger.id}] [user_trigger: #{inspect(user_trigger.id)}]]"
    )

    if length(slugs) > 0 do
      slug = hd(slugs)

      {sanbase_link, short_url_id} =
        case Sanbase.Embed.create_charts_link(metric, slug) do
          {:ok, short_url} ->
            # frontend requires `__sCl` to be apended in order to resolve the short url
            {"#{base_url()}/charts/#{short_url.short_url}__sCl?utm_source=telegram&utm_medium=signals",
             short_url.short_url}

          _ ->
            {"https://app.santiment.net/charts?slug=#{slug}?utm_source=telegram&utm_medium=signals",
             nil}
        end

      Logger.info(
        "[maybe_extend_payload_telegram_channel_#{user_trigger.id}] sanbase_link: #{inspect(sanbase_link)}] [short_url_id: #{inspect(short_url_id)}]"
      )

      payload = """
      #{String.trim_trailing(payload)}

      [View chart on Sanbase](#{sanbase_link})
      [What does this metric mean?](#{Sanbase.Alert.Docs.academy_link(metric)})
      [Open signal on SanR](https://sanr.app/?utm_source=telegram&utm_medium=signals)
      """

      {payload, [short_url_id: short_url_id]}
    else
      {payload, []}
    end
  end

  defp maybe_extend_payload_telegram_channel(payload, _, _), do: {payload, []}

  defp do_send_email(user, payload) do
    payload_html = Earmark.as_html!(payload, breaks: true, timeout: nil, mapper: &Enum.map/2)
    name = Sanbase.Accounts.User.get_name(user)

    try do
      case Sanbase.TemplateMailer.send(user.email, Sanbase.Email.Template.alerts_template(), %{
             name: name,
             username: name,
             payload: payload_html
           }) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, %{reason: :email_send_fail, error: reason}}
      end
    rescue
      e in Jason.DecodeError ->
        Logger.error("Failed to decode Mailjet response: #{inspect(e)}")
        {:error, "Invalid response from email provider"}
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

  defp send_or_limit(channel, %{user: user, trigger: trigger}, limit, send_alert_fun)
       when is_function(send_alert_fun, 2) do
    send_fun = fn {identifier, payload}, list ->
      elem = {identifier, send_alert_fun.(identifier, payload)}
      [elem | list]
    end

    limit_fun = fn {identifier, _payload}, list ->
      elem = {identifier, limits_reached_error_tuple(user, trigger, channel)}
      [elem | list]
    end

    {:ok, %{result: result, remaining_limit: remaining_limit}} =
      Sanbase.EnumUtils.reduce_limited_times(trigger.settings.payload, limit, send_fun, limit_fun)

    if remaining_limit == 0 and limit != 0 do
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

    channels = Settings.alert_channels()

    alerts_fired_today_updated =
      Enum.into(channels, %{}, fn channel ->
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

  defp prod?(), do: Sanbase.Utils.Config.module_get(Sanbase, :deployment_env) == "prod"

  defp preview_url() do
    case prod?() do
      true -> "https://preview.santiment.net"
      false -> "https://preview-stage.santiment.net"
    end
  end

  defp base_url do
    case prod?() do
      true -> "https://app.santiment.net"
      false -> "https://app-stage.santiment.net"
    end
  end

  defp basic_auth_header() do
    credentials =
      (System.get_env("GRAPHQL_BASIC_AUTH_USERNAME") <>
         ":" <> System.get_env("GRAPHQL_BASIC_AUTH_PASSWORD"))
      |> Base.encode64()

    {"Authorization", "Basic #{credentials}"}
  end
end
