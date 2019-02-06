defmodule Sanbase.Signals.Scheduler do
  alias Sanbase.Signals.Trigger.{DailyActiveAddressesSettings, PricePercentChangeSettings}
  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signal

  require Logger

  def run_price_percent_change_signals() do
    type = PricePercentChangeSettings.type()

    type
    |> UserTrigger.get_triggers_by_type()
    |> Evaluator.run()
    |> send_and_mark_as_sent()
    |> log_sent_messages_stats(type)
  end

  def run_daily_active_addresses_signals() do
    type = DailyActiveAddressesSettings.type()

    type
    |> UserTrigger.get_triggers_by_type()
    |> Evaluator.run()
    |> send_and_mark_as_sent()
    |> log_sent_messages_stats(type)
  end

  # Private functions

  defp send_and_mark_as_sent(triggers) do
    triggers
    |> Sanbase.Parallel.pmap_concurrent(
      fn %UserTrigger{} = user_trigger ->
        case Signal.send(user_trigger) do
          :ok ->
            %{user: user, trigger: %{id: trigger_id}} = user_trigger
            UserTrigger.update_user_trigger(user, %{id: trigger_id, last_triggered: Timex.now()})
            :ok

          error ->
            error
        end
      end,
      max_concurrency: 20,
      ordered: false
    )
  end

  defp log_sent_messages_stats([], type) do
    Logger.info("There were no #{type} signals triggered")
  end

  defp log_sent_messages_stats(list, type) do
    successful_messages = list |> Enum.count(fn elem -> elem == :ok end)

    Logger.info(
      "In total #{successful_messages}/#{length(list)} #{type} signals were sent successfully"
    )
  end
end
