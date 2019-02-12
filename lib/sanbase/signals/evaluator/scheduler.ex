defmodule Sanbase.Signals.Scheduler do
  alias Sanbase.Signals.Trigger.{
    DailyActiveAddressesSettings,
    PricePercentChangeSettings,
    PriceAbsoluteChangeSettings,
    TrendingWordsTriggerSettings
  }

  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signal

  require Logger

  def run_price_percent_change_signals() do
    PricePercentChangeSettings.type()
    |> run()
  end

  def run_price_absolute_change_signals() do
    PriceAbsoluteChangeSettings.type()
    |> run
  end

  def run_daily_active_addresses_signals() do
    DailyActiveAddressesSettings.type()
    |> run
  end

  def run_trending_words_signals() do
    TrendingWordsTriggerSettings.type()
    |> run()
  end

  # Private functions

  defp run(type) do
    type
    |> UserTrigger.get_triggers_by_type()
    |> Evaluator.run()
    |> send_and_mark_as_sent()
    |> log_sent_messages_stats(type)
  end

  defp send_and_mark_as_sent(triggers) do
    triggers
    |> Sanbase.Parallel.pmap_concurrent(
      fn %UserTrigger{} = user_trigger ->
        case Signal.send(user_trigger) do
          list when is_list(list) ->
            %{user: user, trigger: %{id: trigger_id, last_triggered: last_triggered}} =
              user_trigger

            now = Timex.now()

            last_triggered =
              Enum.reduce(list, last_triggered, fn
                {slug, :ok}, acc ->
                  Map.put(acc, slug, now)

                _, acc ->
                  acc
              end)

            UserTrigger.update_user_trigger(user, %{
              id: trigger_id,
              last_triggered: last_triggered
            })

            list

          _ ->
            []
        end
      end,
      max_concurrency: 20,
      ordered: false,
      map_type: :flat_map
    )
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
end
