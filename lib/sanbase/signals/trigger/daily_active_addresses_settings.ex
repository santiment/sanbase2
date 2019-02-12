defmodule Sanbase.Signals.Trigger.DailyActiveAddressesSettings do
  @moduledoc ~s"""
  DailyActiveAddressesSettings configures the settings for a signal that is fired
  when the number of daily active addresses for today exceeds the average for the
  `time_window` period of time.
  """
  use Vex.Struct

  import Sanbase.Signals.{Validation, Utils}

  alias __MODULE__
  alias Sanbase.Signals.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Signals.Evaluator.Cache

  @derive Jason.Encoder
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

  validates(:target, &valid_target?/1)
  validates(:channel, inclusion: valid_notification_channels())
  validates(:time_window, &valid_time_window?/1)
  validates(:percent_threshold, &valid_percent?/1)
  validates(:repeating, &is_boolean/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          percent_threshold: number(),
          repeating: boolean(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(settings) do
    {:ok, contract, _token_decimals} = Project.contract_info_by_slug(settings.target)

    current_daa =
      case contract do
        "ETH" ->
          Cache.get_or_store("daa_#{contract}_current", fn ->
            {:ok, result} = EthDailyActiveAddresses.realtime_active_addresses()
            result
          end)

        _ ->
          Cache.get_or_store("daa_#{contract}_current", fn ->
            {:ok, [{_, result}]} = Erc20DailyActiveAddresses.realtime_active_addresses(contract)
            result
          end)
      end

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
      construct_cache_key([
        settings.type,
        settings.target,
        settings.time_window,
        settings.percent_threshold
      ])
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
