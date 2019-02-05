defmodule Sanbase.Signals.Trigger.DailyActiveAddressesSettings do
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

  def get_data(settings) do
    {:ok, contract, _token_decimals} = Project.contract_info_by_slug(settings.target)

    current_daa =
      Cache.get_or_store("daa_#{contract}_current", fn ->
        average_daily_active_addresses(
          contract,
          Timex.shift(Timex.now(), days: -1),
          Timex.now()
        )
      end)

    time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)

    average_daa =
      Cache.get_or_store("daa_#{contract}_prev_#{settings.time_window}", fn ->
        average_daily_active_addresses(
          contract,
          Timex.shift(Timex.now(), seconds: -time_window_sec),
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

  defimpl Sanbase.Signals.Settings, for: DailyActiveAddressesSettings do
    def triggered?(%DailyActiveAddressesSettings{triggered?: triggered}), do: triggered

    def evaluate(%DailyActiveAddressesSettings{} = settings) do
      {current_daa, average_daa} = DailyActiveAddressesSettings.get_data(settings)

      case percent_change(average_daa, current_daa) >= settings.percent_threshold do
        true ->
          %DailyActiveAddressesSettings{
            settings
            | triggered?: true,
              payload: payload(settings, current_daa, average_daa)
          }

        _ ->
          %DailyActiveAddressesSettings{settings | triggered?: false}
      end
    end

    def cache_key(%DailyActiveAddressesSettings{} = settings) do
      data =
        [settings.type, settings.target, settings.time_window, settings.percent_threshold]
        |> Jason.encode!()

      :crypto.hash(:sha256, data)
      |> Base.encode16()
    end

    defp chart_url(project) do
      Sanbase.Chart.build_embedded_chart(
        project,
        Timex.shift(Timex.now(), days: -90),
        Timex.now(),
        chart_type: :daily_active_addresses
      )
      |> case do
        [%{image: %{url: chart_url}}] -> chart_url
        _ -> nil
      end
    end

    defp payload(settings, current_daa, average_daa) do
      project = Project.by_slug(settings.target)

      """
      **#{project.name}** Daily Active Addresses has gone up by **#{
        percent_change(average_daa, current_daa)
      }%** for the last 1 day.
      Average Daily Active Addresses for last **#{
        Sanbase.DateTimeUtils.compound_duration_to_text(settings.time_window)
      }**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHCL price chart for the past 90 days](#{
        chart_url(project)
      })
      """
    end
  end
end
