defmodule Sanbase.Signals.Scheduler do
  alias Sanbase.Signals.Trigger.{DailyActiveAddressesSettings, PricePercentChangeSettings}
  alias Sanbase.Signals.UserTrigger
  alias Sanbase.Signals.Evaluator
  alias Sanbase.Signal

  require Logger

  def run_price_signals() do
    PricePercentChangeSettings.type()
    |> UserTrigger.get_triggers_by_type()
    |> Evaluator.run()
    |> send_and_mark_as_sent()
  end

  def run_daa_signals() do
    DailyActiveAddressesSettings.type()
    |> UserTrigger.get_triggers_by_type()
    |> Evaluator.run()
    |> send_and_mark_as_sent()
  end

  # Private functions

  defp send_and_mark_as_sent(triggers) do
    triggers
    |> Enum.each(fn %UserTrigger{} = user_trigger ->
      case Signal.send(user_trigger) do
        :ok ->
          %{user: user, trigger: %{id: trigger_id}} = user_trigger
          UserTrigger.update_user_trigger(user, %{id: trigger_id, last_triggered: Timex.now()})
          :ok

        {:error, error} = error_tuple ->
          Logger.warn("Cannot send a signal. Reason: #{inspect(error)}")
          error_tuple
      end
    end)
  end
end
