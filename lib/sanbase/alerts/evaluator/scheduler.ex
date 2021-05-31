defmodule Sanbase.Alert.Scheduler do
  @moduledoc ~s"""
  This module is the entrypoint to the user custom alerts.
  It's main job is to execute the whole glue all modules related to alert processing
  into one pipeline (the `run/0` function):
  > Get the user triggers from the database
  > Evaluate the alerts
  > Send the alerts to the user
  > Update the `last_triggered` in the database
  > Log stats messages
  """

  @alert_modules Sanbase.Alert.List.get()

  alias Sanbase.Alert.{UserTrigger, HistoricalActivity}
  alias Sanbase.Alert.Evaluator
  alias Sanbase.Alert

  require Logger

  defguard is_non_empty_map(map) when is_map(map) and map != %{}

  @doc ~s"""
  Process for all active alerts with the given type. The processing
   includes the following steps:
   1. Fetch the active alerts with the given type.
   2. Evaluate the alerts
   3. Send the evaluated alerts to the proper channels
      Note: A user can receive only a limited number of alerts per day, so
      if this limit is reached only one more notification will be send about
      the limit reached with a CTA to increase the number of alert per day
      or just look at the events on the sanbase feed.
    4. Update the alerts and users records appropriately.
  """
  def run_alert(module)

  for module <- @alert_modules do
    def run_alert(unquote(module)) do
      unquote(module).type() |> run()
    end
  end

  # Private functions

  @batch_size 200
  defp run(type) do
    Logger.info("Schedule evaluation for the alerts of type #{type}")

    run_uuid = UUID.uuid4() |> String.split("-") |> List.first()

    info_map = %{type: type, run_uuid: run_uuid, batch_size: @batch_size}

    alerts =
      type
      |> UserTrigger.get_active_triggers_by_type()
      |> filter_receivable_triggers(info_map)

    # The batches are run sequentially for now. If they start running in parallel
    # the batches creation becomes more complicated - all the alerts of a user
    # must end up in a single batch so no race conditions updating the DB can occur.
    batches =
      alerts
      |> Enum.chunk_every(@batch_size)

    alerts_count = length(alerts)

    # Extend the info map with the data that is not not prior the first definition
    # of it.
    info_map =
      Map.merge(info_map, %{
        alerts_count: alerts_count,
        batches_count: length(batches)
      })

    Logger.info("""
    [#{info_map.run_uuid}] Start evaluating alerts of type #{type} in batches. \
    In total #{alerts_count} alerts will be processed in #{info_map.batches_count} \
    #{if info_map.batches_count == 1, do: "batch", else: "batches"} of size #{@batch_size}.
    """)

    run_batches(batches, info_map)
  end

  defp run_batches([], info_map) do
    Logger.info("""
    [#{info_map.run_uuid}] There are no active alerts of type #{info_map.type} \
    to be run.
    """)
  end

  defp run_batches(trigger_batches, info_map) do
    trigger_batches
    |> Enum.with_index(1)
    |> Enum.each(fn {triggers_batch, index} ->
      try do
        info_map = Map.put(info_map, :index, index)
        run_batch(triggers_batch, info_map)
      rescue
        e ->
          Logger.error("""
          [#{info_map.run_uuid}] Raised an exception while evaluating alerts of type #{
            info_map.type
          } - batch #{index}. \

          #{Exception.format(:error, e, __STACKTRACE__)}
          """)
      end
    end)
  end

  defp run_batch(triggers_batch, info_map) do
    %{type: type} = info_map
    log_current_batch_message(info_map)

    {updated_user_triggers, sent_list_results} =
      triggers_batch
      |> Evaluator.run(type)
      |> send_and_mark_as_sent()

    fired_alerts =
      updated_user_triggers
      |> get_fired_alerts_data()

    fired_alerts |> persist_historical_activity()
    fired_alerts |> persist_timeline_events()

    updated_user_triggers |> deactivate_non_repeating()

    sent_list_results
    |> List.flatten()
    |> log_sent_messages_stats(type, info_map)
  end

  defp log_current_batch_message(info_map) do
    %{
      type: type,
      index: index,
      alerts_count: alerts_count,
      batches_count: batches_count,
      batch_size: batch_size,
      run_uuid: run_uuid
    } = info_map

    from_alert = (index - 1) * batch_size
    to_alert = Enum.min([alerts_count, index * batch_size])

    Logger.info("""
    [#{run_uuid}] Run batch of alerts of type #{type}. Batch #{index}/#{batches_count}, \
    Alerts #{from_alert}-#{to_alert}/#{alerts_count}.
    """)
  end

  defp filter_receivable_triggers(user_triggers, info_map) do
    %{type: type, run_uuid: run_uuid} = info_map

    filtered =
      Enum.filter(user_triggers, fn %{trigger: trigger, user: user} ->
        channels = List.wrap(trigger.settings.channel)

        channels != [] and
          Enum.any?(channels, fn
            "email" -> Sanbase.Accounts.User.can_receive_email_alert?(user)
            "telegram" -> Sanbase.Accounts.User.can_receive_telegram_alert?(user)
            # The other types - telegram channel and webhooks are always enabled
            # and cannot be disabled by some settings.
            _ -> true
          end)
      end)

    total_count = length(user_triggers)
    disabled_count = total_count - length(filtered)

    Logger.info("""
    [#{run_uuid}] In total #{disabled_count}/#{total_count} active alerts of type \
    #{type} are not being computed because they cannot be sent. The owners of \
    these alerts have disabled the notification channels or has no telegram/email \
    linked to their account.
    """)

    filtered
  end

  defp deactivate_non_repeating(triggers) do
    for %UserTrigger{id: id, user: user, trigger: %{is_repeating: false}} <- triggers do
      UserTrigger.update_user_trigger(user, %{
        id: id,
        is_active: false
      })
    end
  end

  # returns a tuple {updated_user_triggers, send_result_list}
  defp send_and_mark_as_sent(triggers) do
    # Group by user. Separate user groups can be executed concurrently, but
    # the triggers of the same user must not be concurrent. By doing this we
    # drop the Mutex dependency while sending notifications that were necessary
    # so the alerts sent can be tracked properly. If two triggers for the same
    # user are executed concurrently, the `max_alerts_to_sent` cannot be enforced
    # without using any synchronization technique.
    grouped_by_user = Enum.group_by(triggers, fn %{user: user} -> user.id end)

    grouped_by_user
    |> Sanbase.Parallel.map(
      fn {_user_id, triggers} -> send_triggers_sequentially(triggers) end,
      max_concurrency: 15,
      ordered: false,
      map_type: :flat_map
    )
    |> Enum.unzip()
  end

  defp send_triggers_sequentially(triggers) do
    triggers
    |> Enum.map(fn %UserTrigger{} = user_trigger ->
      case Alert.send(user_trigger) do
        [] ->
          {user_trigger, []}

        list when is_list(list) ->
          {:ok, %{last_triggered: last_triggered}} = handle_send_results_list(user_trigger, list)

          user_trigger = update_trigger_last_triggered(user_trigger, last_triggered)
          {user_trigger, list}
      end
    end)
  end

  defp update_trigger_last_triggered(user_trigger, last_triggered) do
    {:ok, updated_user_trigger} =
      UserTrigger.update_user_trigger(user_trigger.user, %{
        id: user_trigger.id,
        last_triggered: last_triggered,
        settings: user_trigger.trigger.settings
      })

    put_in(
      user_trigger.trigger.last_triggered,
      updated_user_trigger.trigger.last_triggered
    )
  end

  defp handle_send_results_list(
         %{trigger: %{last_triggered: last_triggered}},
         send_results_list
       ) do
    # Round the datetimes 30 seconds because the `last_triggered` is used as
    # part of a cache key. If `now` is left as is the last triggered time of
    # all alerts will be different, sometimes only by a second
    now =
      Timex.now()
      |> Sanbase.DateTimeUtils.round_datetime(second: 30)
      |> Timex.set(microsecond: {0, 0})

    # Update all triggered_at regardless if the send to the channel succeed
    # because the alert will be stored in the timeline events.
    # Keep count of the total alerts triggered and the number of alerts
    # that were not sent succesfully. Reasons can be:
    # - missing email/telegram linked when such channel is chosen;
    # - webhook failed to be sent;
    # - daily alerts limit is reached;
    failed_count = fn failed, result ->
      failed + if result == :ok, do: 0, else: 1
    end

    {last_triggered, total_triggered, total_failed} =
      send_results_list
      |> Enum.reduce({last_triggered, _total = 0, _failed = 0}, fn
        {list, result}, {acc, total, failed} when is_list(list) ->
          # Example: {["elem1", "elem2"], :ok}.
          # This case happens when multiple identifiers (for example emerging words)
          # are handled in one notification.
          acc = Enum.reduce(list, acc, &Map.put(&2, &1, now))

          {acc, total + 1, failed_count.(failed, result)}

        {identifier, result}, {acc, total, failed} ->
          # Example: {"santiment", :ok}.
          # This is the most common case - one notification per identificator.

          acc = Map.put(acc, identifier, now)
          {acc, total + 1, failed_count.(failed, result)}
      end)

    {:ok,
     %{
       last_triggered: last_triggered,
       total_triggered: total_triggered,
       total_sent_succesfully: total_triggered - total_failed,
       total_sent_failed: total_failed
     }}
  end

  defp get_fired_alerts_data(user_triggers) do
    user_triggers
    |> Enum.map(fn
      %UserTrigger{
        id: id,
        user_id: user_id,
        trigger: %{
          settings: %{triggered?: true, payload: payload, template_kv: template_kv},
          last_triggered: last_triggered
        }
      }
      when is_non_empty_map(last_triggered) ->
        identifier_kv_map =
          template_kv
          |> Enum.into(%{}, fn {identifier, {_template, kv}} -> {identifier, kv} end)

        %{
          user_trigger_id: id,
          user_id: user_id,
          payload: payload,
          triggered_at: max_last_triggered(last_triggered) |> DateTime.to_naive(),
          data: %{user_trigger_data: identifier_kv_map}
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  # Fixme: remove after frontend migrates to use only Timeline Events
  defp persist_historical_activity(fired_triggers) do
    fired_triggers
    |> Enum.chunk_every(200)
    |> Enum.each(fn chunk ->
      Sanbase.Repo.insert_all(HistoricalActivity, chunk)
    end)
  end

  defp persist_timeline_events(fired_triggers) do
    fired_triggers
    |> Sanbase.Timeline.TimelineEvent.create_trigger_fired_events()
  end

  defp log_sent_messages_stats([], type, info_map) do
    Logger.info("[#{info_map.run_uuid}] There were no #{type} alerts triggered.")
  end

  defp log_sent_messages_stats(list, type, info_map) do
    list_length = length(list)
    successful_messages_count = list |> Enum.count(fn {_elem, status} -> status == :ok end)
    errors = for {_, {:error, error}} <- list, do: error

    if successful_messages_count + length(errors) != list_length do
      Logger.error("""
      [#{info_map.run_uuid}] Some of the sent alerts of type #{type} have returned \
      a result format that is not recognizned neither as :ok nor as :error case.
      """)
    end

    Enum.each(errors, fn error ->
      Logger.warn("[#{info_map.run_uuid}] Cannot send a #{type} alert. Reason: #{inspect(error)}")
    end)

    errors_to_count_map =
      errors
      |> Enum.group_by(fn
        %{reason: reason} -> reason
        _ -> :unspecified
      end)
      |> Map.new(fn {reason, list} -> {reason, length(list)} end)
      |> Enum.reject(fn {_reason, count} -> count == 0 end)
      |> Map.new()

    fail_reasons =
      Enum.map(errors_to_count_map, fn {reason, count} ->
        "#{count} failed with the reason #{reason}\n"
      end)

    Logger.info("""
    [#{info_map.run_uuid}] In total #{successful_messages_count}/#{list_length} \
    #{type} alerts were sent successfully.
    #{fail_reasons}
    """)
  end

  defp max_last_triggered(last_triggered) when is_non_empty_map(last_triggered) do
    last_triggered
    |> Map.values()
    |> Enum.map(fn
      %DateTime{} = dt ->
        dt

      datetime_str when is_binary(datetime_str) ->
        Sanbase.DateTimeUtils.from_iso8601!(datetime_str)
    end)
    |> Enum.max_by(&DateTime.to_unix/1)
  end
end
