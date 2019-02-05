defmodule Sanbase.Signals.Trigger.DailyActiveAddressesTriggerSettings do
  @derive [Jason.Encoder]
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  import Sanbase.Signals.Utils

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Signals.Evaluator.Cache

  @spec type() :: String.t()
  def type(), do: @trigger_type

  def get_data(trigger) do
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
      Cache.get_or_store("daa_#{contract}_prev_#{trigger.time_window}", fn ->
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

  defimpl Sanbase.Signals.Triggerable, for: DailyActiveAddressesTriggerSettings do
    def triggered?(%DailyActiveAddressesTriggerSettings{triggered?: triggered}), do: triggered

    def evaluate(%DailyActiveAddressesTriggerSettings{} = trigger) do
      {current_daa, average_daa} = DailyActiveAddressesTriggerSettings.get_data(trigger)

      case percent_change(average_daa, current_daa) >= trigger.percent_threshold do
        true ->
          %DailyActiveAddressesTriggerSettings{
            trigger
            | triggered?: true,
              payload: trigger_payload(trigger, current_daa, average_daa)
          }

        _ ->
          %DailyActiveAddressesTriggerSettings{trigger | triggered?: false}
      end
    end

    def cache_key(%DailyActiveAddressesTriggerSettings{} = trigger) do
      data =
        [trigger.type, trigger.target, trigger.time_window, trigger.percent_threshold]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end

    defp trigger_payload(trigger, current_daa, average_daa) do
      project = Project.by_slug(trigger.target)

      payload = """
      **#{project.name}** Daily Active Addresses has gone up by **#{
        percent_change(average_daa, current_daa)
      }%** for the last #{Sanbase.DateTimeUtils.compound_duration_to_text(trigger.time_window)}.
      Average Daily Active Addresses for last **#{
        Sanbase.DateTimeUtils.compound_duration_to_text(trigger.time_window)
      }**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}
      """

      seconds = Sanbase.DateTimeUtils.compound_duration_to_seconds(trigger.time_window)

      embeds =
        Sanbase.Chart.build_embedded_chart(
          project,
          Timex.shift(Timex.now(), seconds: -seconds),
          Timex.now(),
          chart_type: :daily_active_addresses
        )

      {payload, embeds}
    end
  end
end
