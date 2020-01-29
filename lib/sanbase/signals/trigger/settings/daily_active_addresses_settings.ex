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
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_days: 1, interval_to_str: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.DailyActiveAddresses
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :operation]
  defstruct type: @trigger_type,
            target: nil,
            channel: nil,
            time_window: "2d",
            operation: nil,
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:time_window, &time_window_is_whole_days?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    time_window_in_days = Enum.max([str_to_days(settings.time_window), 1])
    # Ensure there are enough data points in the interval. The not needed
    # ones are ignored
    from = Timex.shift(Timex.now(), days: -(3 * time_window_in_days))
    to = Timex.now()

    contract_info_map = Project.List.contract_info_map()

    target_list
    |> Enum.map(fn slug ->
      with {contract, _token_decimals} when not is_nil(contract) <-
             Map.get(contract_info_map, slug),
           daa when length(daa) >= time_window_in_days <-
             fetch_daily_active_addersses(contract, from, to, "1d") do
        last = List.last(daa)
        previous = Enum.at(daa, -time_window_in_days)
        daily_active_addresses = [previous, last]
        {slug, daily_active_addresses}
      else
        _ -> nil
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
        {:ok, result} -> result
        _ -> []
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
      ResultBuilder.build(data, settings, &template_kv/2, value_key: :active_addresses)
    end

    def cache_key(%DailyActiveAddressesSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.time_window,
        settings.operation
      ])
    end

    defp template_kv(%{identifier: slug} = values, settings) do
      %{current: current_daa, previous_average: average_daa} = values

      project = Project.by_slug(slug)
      interval = interval_to_str(settings.time_window)

      kv = %{
        project_name: project.name,
        daily_active_addresses: current_daa,
        average_daily_active_addresses: average_daa,
        movement_text: Sanbase.Signal.OperationText.to_text(values, settings.operation),
        interval: interval,
        project_link: Project.sanbase_link(project),
        chart_url: chart_url(project, {:metric, "daily_active_addresses"}),
        chart_url_alt_text:
          "Daily Active Addresses chart and OHLC price chart for the past 90 days"
      }

      template = """
      **{{project_name}}**'s Daily Active Addresses {{movement_text}} up to {{daily_active_addresses}} active addresses.

      Average Daily Active Addresses for last **{{interval}}*: **{{average_daily_active_addresses}}**.
      More info here: {{project_link}}

      ![{{chart_url_alt_text}}]({{chart_url}})
      """

      {template, kv}
    end
  end
end
