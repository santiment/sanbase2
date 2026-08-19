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

  alias Sanbase.Accounts.User
  alias Sanbase.Alert.{Trigger, UserTrigger, HistoricalActivity}
  alias Sanbase.Alert.Evaluator
  alias Sanbase.Alert.Validation.NotificationChannel
  alias Sanbase.Alert

  import Sanbase.Alert.EventEmitter, only: [emit_event: 3]

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

  def run_alert(module) do
    case module in Alert.List.get() do
      true ->
        run(module.type())

      false ->
        raise(
          "Module #{inspect(module)} is not in the modules list defined in Sanbase.Alert.List"
        )
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
      |> filter_and_deactivate_webhook_bad_url_triggers(info_map)
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
    # The state is a list of mapsets, each slightly larger than @batch_size. All of a
    # user's alerts go in the same batch so batches can run concurrently. The initial state
    # holds an empty mapset, so with no alerts the result needs Enum.reject(&Enum.empty?).
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

  # Turn the batches from lists into maps, adding the number of alerts in the batch and
  # which part of the whole alerts list it covers.
  defp batches_to_maps(batches) do
    batches
    |> Enum.reduce({[], 0}, fn alerts, {batches, size_so_far} ->
      elem = %{
        alerts: Enum.to_list(alerts),
        batch_size: MapSet.size(alerts),
        alerts_from: size_so_far,
        alerts_to: size_so_far + MapSet.size(alerts)
      }

      {[elem | batches], elem.alerts_to + 1}
    end)
    |> elem(0)
    # Reverse so the `alerts_from: 0` is first in the list, not last
    |> Enum.reverse()
  end

  defp run_batches([], info_map) do
    Logger.info("""
    [#{info_map.run_uuid}] There are no active alerts of type #{info_map.type} \
    to be run.
    """)

    []
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
      |> Enum.zip(sent_list_results)
      |> get_fired_alerts_data()

    fired_alerts |> persist_historical_activity()

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
    with size #{batch_map.batch_size}. \
    Alerts #{batch_map.alerts_from}-#{Enum.min([batch_map.alerts_to, alerts_count])} \
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

    if frozen_count > 0 do
      Logger.info("""
      [#{run_uuid}] In total #{frozen_count}/#{total_count} active receivable alerts of type \
      #{type} are frozen and won't be processed.
      """)
    end

    filtered
  end

  # Deactivate legacy alerts whose only destinations are webhooks with invalid URLs (http
  # scheme, IP address host, malformed) - they can deliver nothing. Alerts with other
  # channels too are kept; their invalid webhook is refused at send time instead.
  defp filter_and_deactivate_webhook_bad_url_triggers(user_triggers, info_map) do
    {bad_url_triggers, rest} =
      Enum.split_with(user_triggers, &only_bad_webhook_url_channels?/1)

    for %UserTrigger{} = ut <- bad_url_triggers do
      Logger.info("""
      [#{info_map.run_uuid}] Deactivating alert with id #{ut.id} because its only \
      destinations are webhooks with invalid URLs.
      """)

      UserTrigger.update_is_active(ut.id, ut.user_id, false)
    end

    rest
  end

  defp only_bad_webhook_url_channels?(%UserTrigger{trigger: %{settings: %{channel: channel}}}) do
    case List.wrap(channel) do
      [] -> false
      entries -> Enum.all?(entries, &bad_webhook_url_entry?/1)
    end
  end

  defp only_bad_webhook_url_channels?(_user_trigger), do: false

  # True only for webhook entries whose URL fails validation. Entries of
  # other channel types are not bad entries.
  defp bad_webhook_url_entry?(entry) do
    with {:ok, url} <- NotificationChannel.webhook_url(entry),
         {:error, _} <- Sanbase.Utils.Validation.valid_webhook_url?(url) do
      true
    else
      _ -> false
    end
  end

  defp filter_receivable_triggers(user_triggers, info_map) do
    %{type: type, run_uuid: run_uuid} = info_map

    filtered =
      Enum.filter(user_triggers, fn %{trigger: trigger, user: user} = ut ->
        channels = List.wrap(trigger.settings.channel)

        channels != [] and
          Enum.any?(channels, &channel_receivable?(&1, user, ut))
      end)

    total_count = length(user_triggers)
    disabled_count = total_count - length(filtered)

    if disabled_count > 0 do
      Logger.info("""
      [#{run_uuid}] In total #{disabled_count}/#{total_count} active alerts of type \
      #{type} are not being computed because they cannot be sent. The owners of \
      these alerts have disabled the notification channels or has no telegram/email \
      linked to their account.
      """)
    end

    filtered
  end

  # web push cannot be received currently, so its presence alone is not enough
  # to schedule the alert.
  defp channel_receivable?("email", user, _ut), do: User.Alert.can_receive_email_alert?(user)

  defp channel_receivable?("telegram", user, _ut),
    do: User.Alert.can_receive_telegram_alert?(user)

  defp channel_receivable?("web_push", _user, _ut), do: false

  defp channel_receivable?(%{"webhook" => url}, user, _ut),
    do: User.Alert.can_receive_webhook_alert?(user, url)

  defp channel_receivable?(%{webhook: url}, user, _ut),
    do: User.Alert.can_receive_webhook_alert?(user, url)

  defp channel_receivable?(%{"telegram_channel" => chat_id}, user, _ut),
    do: User.Alert.can_receive_telegram_channel_alert?(user, chat_id)

  defp channel_receivable?(%{telegram_channel: chat_id}, user, _ut),
    do: User.Alert.can_receive_telegram_channel_alert?(user, chat_id)

  # Bare "webhook" / "telegram_channel" strings or any other unknown channel
  # cannot deliver — no URL / chat id to send to. Skip evaluation entirely so
  # the alert does not waste resources or crash later in send_to_channel/3.
  defp channel_receivable?(channel, _user, ut) do
    Logger.warning(
      "Skipping alert evaluation: unsupported notification channel #{inspect(channel)} for user_trigger_id=#{ut.id}"
    )

    false
  end

  defp deactivate_non_repeating(triggers) do
    for %UserTrigger{id: ut_id, user: user, trigger: %{is_repeating: false}} <-
          triggers do
      UserTrigger.update_is_active(ut_id, user.id, false)
    end
  end

  # returns a tuple {updated_user_triggers, send_result_list}
  defp send_and_mark_as_sent(triggers, info_map) do
    # Group by user: separate user groups run concurrently, the triggers of one user must
    # not. That drops the Mutex dependency the notification sending needed to track sent
    # alerts - with two triggers of the same user running concurrently,
    # `max_alerts_to_sent` cannot be enforced without synchronization.
    grouped_by_user = Enum.group_by(triggers, fn %{user: user} -> user.id end)

    # On timeout, the map returns {:error, :timeout} tuple, so instead of using map_type: :flat_map,
    # we need to use map_type: :map and flatten the result with List.flatten/1, otherwise
    # a matching error is raised
    grouped_by_user
    |> Sanbase.Parallel.map(
      fn {_user_id, triggers} -> send_triggers_sequentially(triggers, info_map) end,
      max_concurrency: 15,
      ordered: false,
      map_type: :map,
      # A killed task loses the not-yet-recorded send results of its in-flight
      # trigger, which resends on the next run. Keep the timeout a generous
      # backstop so that does not happen for legitimately slow rounds.
      timeout: 60_000,
      on_timeout: :kill_task
    )
    |> List.flatten()
    |> Enum.reject(&match?({:exit, :timeout}, &1))
    |> report_sending_alert_timeout(triggers, info_map)
    |> Enum.unzip()
  end

  def send_triggers_sequentially(triggers, info_map) do
    triggers
    |> Enum.map(fn %UserTrigger{} = user_trigger ->
      case Alert.send(user_trigger) do
        [] ->
          {user_trigger, []}

        list when is_list(list) ->
          {:ok, send_results_map} = handle_send_results_list(user_trigger, list)

          user_trigger = update_trigger_after_send(user_trigger, send_results_map, info_map)

          if send_results_map.any_success? do
            emit_event({:ok, user_trigger}, :alert_triggered, %{})
          end

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

  defp update_trigger_after_send(user_trigger, send_results_map, info_map) do
    failing_state = Trigger.FailingState.next(user_trigger.trigger, send_results_map)

    deactivation_reason =
      cond do
        Trigger.FailingState.deactivate_now?(send_results_map) ->
          "of permanent send failures: #{inspect(send_results_map.permanent_failure_reasons)}"

        Trigger.FailingState.deactivate?(failing_state) ->
          "sending it failed on #{failing_state.consecutive_failed_days} consecutive days " <>
            "(#{failing_state.failed_attempts} failed sends since #{failing_state.failing_since})"

        true ->
          nil
      end

    {:ok, updated_user_trigger} =
      UserTrigger.record_send_result(user_trigger, %{
        last_triggered: send_results_map.last_triggered,
        failing_state: failing_state,
        deactivate?: deactivation_reason != nil
      })

    if deactivation_reason do
      Logger.info("""
      [#{info_map.run_uuid}] Deactivating alert with id #{user_trigger.id} because \
      #{deactivation_reason}.
      """)
    end

    updated_user_trigger
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
      |> Sanbase.Utils.DateTime.round_datetime(second: 30)
      |> Timex.set(microsecond: {0, 0})

    # Failed sends are not marked as triggered - the alert fires for them
    # again on the next run.
    {last_triggered, any_success?, delivery_failures_count, permanent_failure_reasons} =
      send_results_list
      |> Enum.reduce({last_triggered, false, 0, []}, fn
        {identifier_or_list, _result = :ok}, {acc, _any_success, delivery_failures, permanent} ->
          # Example: {["elem1", "elem2"], :ok} or {"0x4efb548a2cb8f0af7c591cef21053f6875b5d38f", :ok}
          # This case happens when multiple identifiers (for example emerging words)
          # are handled in one notification.
          list = identifier_or_list |> List.wrap()
          acc = Enum.reduce(list, acc, &Map.put(&2, &1, now))

          {acc, true, delivery_failures, permanent}

        {_identifier_or_list, error_result}, {acc, any_success, delivery_failures, permanent} ->
          delivery_failures =
            if Trigger.FailingState.delivery_failure?(error_result),
              do: delivery_failures + 1,
              else: delivery_failures

          permanent =
            case error_result do
              {:error, %{reason: reason}} ->
                if Trigger.FailingState.permanent_failure?(error_result),
                  do: [reason | permanent],
                  else: permanent

              _ ->
                permanent
            end

          {acc, any_success, delivery_failures, permanent}
      end)

    {:ok,
     %{
       last_triggered: last_triggered,
       any_success?: any_success?,
       any_delivery_failure?: delivery_failures_count > 0,
       delivery_failures_count: delivery_failures_count,
       permanent_failure_reasons: Enum.uniq(permanent_failure_reasons),
       all_permanent_failures?:
         send_results_list != [] and
           length(permanent_failure_reasons) == length(send_results_list)
     }}
  end

  # A trigger can be evaluated while all of its deliveries fail. In that case
  # `last_triggered` deliberately remains unchanged so it can be retried, but
  # its old value must not be recorded as a newly fired historical activity.
  defp get_fired_alerts_data(send_results) do
    send_results
    |> Enum.map(fn
      {ut, results} when is_list(results) and results != [] -> fired_alert_data(ut, results)
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fired_alert_data(%UserTrigger{} = ut, results) do
    %{trigger: %{settings: settings, last_triggered: last_triggered}} = ut

    delivered? = Enum.any?(results, fn {_identifier, result} -> result == :ok end)

    if match?(%{triggered?: true}, settings) and delivered? and
         is_non_empty_map(last_triggered) do
      identifier_kv_map =
        settings.template_kv
        |> Enum.into(%{}, fn {identifier, {_, kv}} -> {identifier, kv} end)

      %{
        user_trigger_id: ut.id,
        user_id: ut.user_id,
        payload: settings.payload,
        triggered_at: max_last_triggered(last_triggered) |> DateTime.to_naive(),
        data: %{user_trigger_data: identifier_kv_map}
      }
    end
  end

  # Fixme: remove after frontend migrates to use only Timeline Events
  defp persist_historical_activity(fired_triggers) do
    fired_triggers
    |> Enum.chunk_every(200)
    |> Enum.each(fn chunk ->
      Sanbase.Repo.insert_all(HistoricalActivity, chunk)
    end)
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
      Logger.warning(
        "[#{info_map.run_uuid}] Cannot send a #{type} alert. Reason: #{inspect(error)}"
      )
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
        Sanbase.Utils.DateTime.from_iso8601!(datetime_str)
    end)
    |> Enum.max_by(&DateTime.to_unix/1)
  end
end
