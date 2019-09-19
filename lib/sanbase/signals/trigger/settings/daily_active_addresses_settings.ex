defmodule Sanbase.Signal.Trigger.DailyActiveAddressesSettings do
  @moduledoc ~s"""
  Signals based on the unique number of daily active addresses.

  The signal supports the following operations:
  1. Daily Active Addresses get over or under a given number
  2. Daily Active Addresses change by a given percent compared to the average
     number of daily active addresses over a given time window
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.DailyActiveAddresses
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :operation]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target: %{list: []},
            channel: nil,
            time_window: "2d",
            operation: nil,
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:time_window, &time_window_is_whole_days?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          filtered_target: Type.filtered_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    time_window_sec = str_to_sec(settings.time_window)
    from = Timex.shift(Timex.now(), seconds: -time_window_sec)
    to = Timex.shift(Timex.now(), days: -1)

    contract_info_map = Project.List.contract_info_map()

    target_list
    |> Enum.map(fn slug ->
      case Map.get(contract_info_map, slug) do
        {contract, _token_decimals} when not is_nil(contract) ->
          daily_active_addresses = fetch_daily_active_addersses(contract, from, to, "1d")

          {slug, daily_active_addresses}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_daily_active_addersses(contract, from, to, interval) do
    cache_key =
      {:daa_signal, contract, round_datetime(from, 300), round_datetime(to, 300), interval}
      |> :erlang.phash2()

    Cache.get_or_store(cache_key, fn ->
      case DailyActiveAddresses.average_active_addresses(contract, from, to, interval) do
        {:ok, result} ->
          result

        _ ->
          []
      end
    end)
  end

  defimpl Sanbase.Signal.Settings, for: DailyActiveAddressesSettings do
    alias Sanbase.Signal.ResultBuilder

    def triggered?(%DailyActiveAddressesSettings{triggered?: triggered}), do: triggered

    def evaluate(%DailyActiveAddressesSettings{} = settings, _trigger) do
      case DailyActiveAddressesSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %DailyActiveAddressesSettings{settings | triggered?: false}
      end
    end

    defp build_result(data, %DailyActiveAddressesSettings{} = settings) do
      ResultBuilder.build(data, settings, &payload/2, value_key: :active_addresses)
    end

    def cache_key(%DailyActiveAddressesSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.time_window,
        settings.operation
      ])
    end

    defp payload(%{slug: slug} = values, settings) do
      %{current: current_daa, previous_average: average_daa} = values

      project = Project.by_slug(slug)
      interval = interval_to_str(settings.time_window)

      """
      **#{project.name}**'s Daily Active Addresses #{
        Sanbase.Signal.OperationText.to_text(values, settings.operation)
      }* up to #{current_daa} active addresses.

      Average Daily Active Addresses for last **#{interval}**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHLC price chart for the past 90 days](#{
        chart_url(project, :daily_active_addresses)
      })
      """
    end
  end
end
