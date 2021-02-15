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

  defp run(type) do
    {updated_user_triggers, sent_list_results} =
      type
      |> UserTrigger.get_active_triggers_by_type()
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
    |> log_sent_messages_stats(type)
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
      max_concurrency: 20,
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

  # Note that the `user_trigger` that came as an argument is returned with
  # modified `last_triggered`.
  # TODO: Research if this is really needed
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
    # Round the datetimes to minutes because the `last_triggered` is used as
    # part of a cache key. If `now` is left as is the last triggered time of
    # all alerts will be different, sometimes only by a second
    now = Timex.now() |> Timex.set(second: 0, microsecond: {0, 0})

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

  defp log_sent_messages_stats([], type) do
    Logger.info("There were no #{type} alerts triggered.")
  end

  defp log_sent_messages_stats(list, type) do
    successful_messages_count = list |> Enum.count(fn {_elem, status} -> status == :ok end)
    errors = for {_, {:error, error}} <- list, do: error

    Enum.each(errors, fn error ->
      Logger.warn("Cannot send a #{type} alert. Reason: #{inspect(error)}")
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

    Logger.info("""
    In total #{successful_messages_count}/#{length(list)} #{type} alerts were sent successfully.
    #{
      Enum.map(errors_to_count_map, fn {reason, count} ->
        "#{count} failed with the reason #{reason}\n"
      end)
    }
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
