defmodule Sanbase.Signals.Trigger.DailyActiveAddressesTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false

  import Sanbase.Signals.Utils

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Signals.Evaluator.Cache

  def type(), do: @trigger_type

  defimpl Sanbase.Signals.Triggerable, for: DailyActiveAddressesTriggerSettings do
    def triggered?(%DailyActiveAddressesTriggerSettings{} = trigger) do
      {current_daa, average_daa} = get_data(trigger)

      percent_change(average_daa, current_daa) >= trigger.percent_threshold
    end

    defp get_data(trigger) do
      {:ok, contract, _token_decimals} = Project.contract_info_by_slug(trigger.target)

      current_daa =
        Cache.get_or_store("daa_#{contract}_current", fn ->
          average_daily_active_addresses(
            contract,
            Timex.shift(Timex.now(), days: -1),
            Timex.now()
          )
        end)

      average_daa =
        Cache.get_or_store("daa_#{contract}_prev_#{to_string(trigger.time_window)}", fn ->
          average_daily_active_addresses(
            contract,
            Timex.shift(Timex.now(), days: -trigger.time_window),
            Timex.shift(Timex.now(), days: -1)
          )
        end)

      {current_daa, average_daa}
    end

    defp average_daily_active_addresses("ethereum", from, to) do
      {:ok, result} = EthDailyActiveAddresses.average_active_addresses(from, to)
      result
    end

    defp average_daily_active_addresses(contract, from, to) do
      {:ok, result} = Erc20DailyActiveAddresses.average_active_addresses(contract, from, to)

      case result do
        [{_, value}] -> value
        _ -> 0
      end
    end

    def cache_key(%DailyActiveAddressesTriggerSettings{} = trigger) do
      data =
        [trigger.type, trigger.target, trigger.time_window, trigger.percent_threshold]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end
  end

  defimpl String.Chars, for: DailyActiveAddressesTriggerSettings do
    def to_string(%{} = trigger) do
      "example payload for #{trigger.type}"
    end
  end
end
