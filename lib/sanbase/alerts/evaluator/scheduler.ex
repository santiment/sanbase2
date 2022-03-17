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

  @batch_size 60
  defp run(type) do
    Logger.info("Schedule evaluation for the alerts of type #{type}")

    run_uuid = UUID.uuid4() |> String.split("-") |> List.first()

    info_map = %{type: type, run_uuid: run_uuid, batch_size: @batch_size}

    alerts =
      type
      |> UserTrigger.get_active_triggers_by_type()
      |> filter_receivable_triggers(info_map)
      |> filter_not_frozen_triggers(info_map)

    # The batches are run sequentially for now. If they start running in parallel
    # the batches creation becomes more complicated - all the alerts of a user
    # must end up in a single batch so no race conditions updating the DB can occur.
    batches =
      split_into_batches(alerts)
      |> batches_to_maps()

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
    #{if info_map.batches_count == 1, do: "batch", else: "batches"} of size \
    approximately #{@batch_size}.
    """)

    run_batches(batches, info_map)
  end

  defp split_into_batches(alerts) do
    # The state is going to be a list of mapsets, each of which will have a size
    # slightly larger than the @batch_size. All of a given users' alerts are put
    # in the same batch, so they can be run concurrently. Because the intial state
    # contains an empty mapset, if there are no alerts the result must be run
    # through Enum.reject(&Enum.empty?)
    init_state = [MapSet.new()]

    Enum.group_by(alerts, & &1.user_id)
    |> Enum.reduce(init_state, fn {_user_id, list}, [mapset | rest] = acc ->
      case MapSet.size(mapset) < @batch_size do
        true ->
          [MapSet.union(MapSet.new(list), mapset) | rest]

        false ->
          [MapSet.new(list) | acc]
      end
    end)
    |> Enum.reject(&Enum.empty?/1)
  end

  # Transform the list of batches represented as lists to a list of batches
  # represented as maps. The map includes extra information for the number of
  # alerts in the batch and what part of the whole alerts list this batch
  # covers
  defp batches_to_maps(batches) do
    batches
    |> Enum.reduce({[], 0}, fn alerts, {batches, size_so_far} ->
      elem = %{
        alerts: Enum.to_list(alerts),
        batch_size: MapSet.size(alerts),
        alerts_from: size_so_far,
        alerts_to: size_so_far + MapSet.size(alerts)
      }

      {[elem | batches], size_so_far + elem.alerts_to + 1}
    end)
    |> elem(0)
  end

  defp run_batches([], info_map) do
    Logger.info("""
    [#{info_map.run_uuid}] There are no active alerts of type #{info_map.type} \
    to be run.
    """)
  end

  defp run_batches(trigger_batches, info_map) do
    run_batch_fun = fn {triggers_batch, index} ->
      try do
        info_map = Map.put(info_map, :index, index)
        run_batch(triggers_batch, info_map)
      rescue
        e ->
          Logger.error("""
          [#{info_map.run_uuid}] Raised an exception while evaluating alerts of type #{info_map.type} - batch #{index}.

          #{Exception.format(:error, e, __STACKTRACE__)}
          """)
      end
    end

    trigger_batches
    |> Enum.with_index(1)
    |> Sanbase.Parallel.map(run_batch_fun,
      max_concurrency: 4,
      timeout: 600 * 1000,
      ordered: false,
      on_timeout: :kill_task
    )
  end

  defp run_batch(batch_map, info_map) do
    %{type: type} = info_map
    log_current_batch_message(info_map, batch_map)

    {updated_user_triggers, sent_list_results} =
      batch_map.alerts
      |> Evaluator.run(type)
      |> send_and_mark_as_sent(info_map)

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

  defp log_current_batch_message(info_map, batch_map) do
    %{
      type: type,
      index: index,
      batches_count: batches_count,
      run_uuid: run_uuid,
      alerts_count: alerts_count
    } = info_map

    Logger.info("""
    [#{run_uuid}] Run batch of alerts of type #{type}. Batch #{index}/#{batches_count}, \
    with size #{batch_map.batch_size}. Alerts #{batch_map.alerts_from}-#{batch_map.alerts_to} \
    out of #{alerts_count}.
    """)
  end

  # Do not execute alerts that are frozen. Frozen alerts are alerts
  # that were created more than X days ago and their owner is a free user.
  # This is the current restriction about alerts of free users.
  defp filter_not_frozen_triggers(user_triggers, info_map) do
    %{type: type, run_uuid: run_uuid} = info_map

    filtered =
      Enum.reject(user_triggers, fn %{trigger: trigger} ->
        Map.get(trigger, :is_frozen, false)
      end)

    total_count = length(user_triggers)
    frozen_count = total_count - length(filtered)

    Logger.info("""
    [#{run_uuid}] In total #{frozen_count}/#{total_count} active receivable alerts of type \
    #{type} are frozen and won't be processed.
    """)

    filtered
  end

  defp filter_receivable_triggers(user_triggers, info_map) do
    %{type: type, run_uuid: run_uuid} = info_map

    filtered =
      Enum.filter(user_triggers, fn %{trigger: trigger, user: user} ->
        channels = List.wrap(trigger.settings.channel)

        channels != [] and
          Enum.any?(channels, fn
            "email" ->
              Sanbase.Accounts.User.can_receive_email_alert?(user)

            "telegram" ->
              Sanbase.Accounts.User.can_receive_telegram_alert?(user)

            %{"webhook" => webhook_url} ->
              match?(:ok, Sanbase.Validation.valid_url?(webhook_url))

            _ ->
              true
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
    for %UserTrigger{id: ut_id, user: user, trigger: %{is_repeating: false}} <-
          triggers do
      UserTrigger.update_is_active(ut_id, user, false)
    end
  end

  # returns a tuple {updated_user_triggers, send_result_list}
  defp send_and_mark_as_sent(triggers, info_map) do
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
      map_type: :flat_map,
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> Enum.reject(&match?({:exit, :timeout}, &1))
    |> report_sending_alert_timeout(triggers, info_map)
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

  # This function is called after the timeouts are removed from the result
  # The missing alerts are those which task for sending them to the user timed out
  defp report_sending_alert_timeout(result, triggers, info_map) do
    %{type: type, run_uuid: run_uuid, index: index} = info_map

    sent_trigger_ids = Enum.map(result, fn {ut, _} -> ut.id end)
    all_trigger_ids = Enum.map(triggers, & &1.id)

    case all_trigger_ids -- sent_trigger_ids do
      [] ->
        :ok

      failed_ids ->
        Logger.info("""
        [#{run_uuid}] In total #{length(failed_ids)} triggered alerts of type #{type} \
        from batch #{index} task for sending them timed out. List of timedout alerts: \
        #{Enum.join(failed_ids, ", ")}
        """)
    end

    result
  end

  defp update_trigger_last_triggered(user_trigger, last_triggered) do
    {:ok, updated_user_trigger} =
      UserTrigger.update_user_trigger(user_trigger.user.id, %{
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
        {identifier_or_list, _result = :ok}, {acc, total, failed} ->
          # Example: {["elem1", "elem2"], :ok} or {"0x123", :ok}
          # This case happens when multiple identifiers (for example emerging words)
          # are handled in one notification.
          list = identifier_or_list |> List.wrap()
          acc = Enum.reduce(list, acc, &Map.put(&2, &1, now))

          {acc, total + 1, failed}

        {_identifier_or_list, _error_result}, {acc, total, failed} ->
          {acc, total + 1, failed + 1}
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
          settings: %{
            triggered?: true,
            payload: payload,
            template_kv: template_kv
          },
          last_triggered: last_triggered
        }
      }
      when is_non_empty_map(last_triggered) ->
        identifier_kv_map =
          template_kv
          |> Enum.into(%{}, fn {identifier, {_template, kv}} ->
            {identifier, kv}
          end)

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

  defp max_last_triggered(last_triggered)
       when is_non_empty_map(last_triggered) do
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
