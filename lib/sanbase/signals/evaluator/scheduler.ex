defmodule Sanbase.Signal.Scheduler do
  @moduledoc ~s"""
  This module is the entrypoint to the user custom signals.
  It's main job is to execute the whole glue all modules related to signal processing
  into one pipeline (the `run/0` function):
  > Get the user triggers from the database
  > Evaluate the signals
  > Send the signals to the user
  > Update the `last_triggered` in the database
  > Log stats messages
  """

  @signal_modules Sanbase.Signal.List.get()

  alias Sanbase.Signal.{UserTrigger, HistoricalActivity}
  alias Sanbase.Signal.Evaluator
  alias Sanbase.Signal

  require Logger

  defguard is_non_empty_map(map) when is_map(map) and map != %{}

  for module <- @signal_modules do
    def run_signal(unquote(module)) do
      unquote(module).type() |> run()
    end
  end

  # Private functions

  defp run(type) do
    {updated_user_triggers, sent_list_results} =
      type
      |> UserTrigger.get_active_triggers_by_type()
      |> Evaluator.run(type)
      |> filter_triggered?()
      |> send_and_mark_as_sent()

    updated_user_triggers
    |> persist_sent_signals()

    updated_user_triggers
    |> deactivate_non_repeating()

    sent_list_results
    |> List.flatten()
    |> log_sent_messages_stats(type)
  end

  defp filter_triggered?(triggers) do
    triggers
    |> Enum.filter(fn
      %UserTrigger{
        trigger: %{
          settings: %{triggered?: triggered?}
        }
      } ->
        triggered?
    end)
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
    triggers
    |> Sanbase.Parallel.map(
      fn %UserTrigger{} = user_trigger ->
        case Signal.send(user_trigger) do
          [] ->
            {user_trigger, []}

          {:error, _} ->
            {user_trigger, []}

          list when is_list(list) ->
            {:ok, updated_user_trigger} = update_last_triggered(user_trigger, list)

            user_trigger =
              put_in(
                user_trigger.trigger.last_triggered,
                updated_user_trigger.trigger.last_triggered
              )

            {user_trigger, list}
        end
      end,
      max_concurrency: 20,
      ordered: false,
      map_type: :map
    )
    |> Enum.unzip()
  end

  defp update_last_triggered(
         %{
           user: user,
           id: trigger_id,
           trigger: %{last_triggered: last_triggered}
         },
         send_results_list
       ) do
    # Round the datetimes to minutes because the `last_triggered` is used as
    # part of a cache key. If `now` is left as is the last triggered time of
    # all signals will be different, sometimes only by a second
    now = Timex.now() |> Timex.set(second: 0, microsecond: {0, 0})

    last_triggered =
      send_results_list
      |> Enum.reduce(last_triggered, fn
        {slug, :ok}, acc ->
          Map.put(acc, slug, now)

        _, acc ->
          acc
      end)

    UserTrigger.update_user_trigger(user, %{
      id: trigger_id,
      last_triggered: last_triggered
    })
  end

  defp persist_sent_signals(user_triggers) do
    user_triggers
    |> Enum.map(fn
      %UserTrigger{
        id: id,
        user_id: user_id,
        trigger: %{
          settings: %{triggered?: true, payload: payload},
          last_triggered: last_triggered
        }
      }
      when is_non_empty_map(last_triggered) ->
        %{
          user_trigger_id: id,
          user_id: user_id,
          payload: payload,
          triggered_at: max_last_triggered(last_triggered)
        }

      _ ->
        nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.chunk_every(200)
    |> Enum.each(fn chunk ->
      Sanbase.Repo.insert_all(HistoricalActivity, chunk)
    end)
  end

  defp log_sent_messages_stats([], type) do
    Logger.info("There were no signals triggered of type #{type}")
  end

  defp log_sent_messages_stats(list, type) do
    successful_messages = list |> Enum.count(fn {_elem, status} -> status == :ok end)

    Logger.info(
      "In total #{successful_messages}/#{length(list)} #{type} signals were sent successfully"
    )
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
