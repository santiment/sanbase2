defmodule Sanbase.Signals.Trigger.DailyActiveAddressesSettings do
  @moduledoc ~s"""
  DailyActiveAddressesSettings configures the settings for a signal that is fired
  when the number of daily active addresses for today exceeds the average for the
  `time_window` period of time by `percent_threshold`.
  """
  use Vex.Struct

  import Sanbase.Signals.{Validation, Utils}

  alias __MODULE__
  alias Sanbase.Signals.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Signals.Evaluator.Cache

  use Vex.Struct

  import Sanbase.Signals.Utils
  import Sanbase.Signals.Validation

  alias __MODULE__
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.{Erc20DailyActiveAddresses, EthDailyActiveAddresses}
  alias Sanbase.Signals.Evaluator.Cache
  alias Sanbase.DateTimeUtils
  alias Sanbase.Signals.Type

  @derive [Jason.Encoder]
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target_list: [],
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            repeating: false,
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
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

<<<<<<< HEAD
  @spec type() :: Type.trigger_type()
=======
  @spec type() :: String.t()
>>>>>>> Add api endpoint
  def type(), do: @trigger_type

<<<<<<< HEAD
  def get_data(%__MODULE__{filtered_target_list: target_list} = settings)
      when is_list(target_list) do
    time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)
=======
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

    time_window_sec = DateTimeUtils.compound_duration_to_seconds(settings.time_window)
>>>>>>> Create signal history protocol. Move history points in separate module

    target_list
    |> Enum.map(fn slug ->
      {:ok, contract, _token_decimals} = Project.contract_info_by_slug(slug)

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

      average_daa =
        Cache.get_or_store("daa_#{contract}_prev_#{settings.time_window}", fn ->
          average_daily_active_addresses(
            contract,
            Timex.shift(Timex.now(), seconds: -time_window_sec),
            Timex.shift(Timex.now(), days: -1)
          )
        end)

      {slug, {current_daa, average_daa}}
    end)
  end

  # private functions

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
      case DailyActiveAddressesSettings.get_data(settings) do
        list when is_list(list) and list != [] ->
          build_result(list, settings)

        _ ->
          %DailyActiveAddressesSettings{settings | triggered?: false}
      end
    end

    defp build_result(
           list,
           %DailyActiveAddressesSettings{
             percent_threshold: percent_threshold,
             time_window: time_window
           } = settings
         ) do
      payload =
        list
        |> Enum.map(fn {slug, {current_daa, previous_daa}} ->
          {slug, current_daa, previous_daa, percent_change(previous_daa, current_daa)}
        end)
        |> Enum.reduce(%{}, fn
          {slug, current_daa, previous_daa, percent_change}, acc
          when percent_change >= percent_threshold ->
            Map.put(acc, slug, payload(slug, time_window, current_daa, previous_daa))

          _, acc ->
            acc
        end)

      %DailyActiveAddressesSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
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

    defp payload(slug, time_window, current_daa, average_daa) do
      project = Project.by_slug(slug)

      """
      **#{project.name}** Daily Active Addresses has gone up by **#{
        percent_change(average_daa, current_daa)
      }%** for the last 1 day.
      Average Daily Active Addresses for last **#{
<<<<<<< HEAD
        Sanbase.DateTimeUtils.compound_duration_to_text(time_window)
=======
        DateTimeUtils.compound_duration_to_text(settings.time_window)
>>>>>>> Create signal history protocol. Move history points in separate module
      }**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHCL price chart for the past 90 days](#{
        chart_url(project)
      })
      """
    end
  end
end
