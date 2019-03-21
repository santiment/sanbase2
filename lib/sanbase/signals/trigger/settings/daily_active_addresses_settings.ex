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
  alias Sanbase.Clickhouse.DailyActiveAddresses
  alias Sanbase.Signals.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "daily_active_addresses"
  @enforce_keys [:type, :target, :channel, :time_window, :percent_threshold]
  defstruct type: @trigger_type,
            target: nil,
            filtered_target: %{list: []},
            channel: nil,
            time_window: nil,
            percent_threshold: nil,
            triggered?: false,
            payload: nil

  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:percent_threshold, &valid_percent?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          target: Type.complex_target(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          percent_threshold: number(),
          triggered?: boolean(),
          payload: Type.payload()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    time_window_sec = Sanbase.DateTimeUtils.compound_duration_to_seconds(settings.time_window)
    from = Timex.shift(Timex.now(), seconds: -time_window_sec)
    to = Timex.shift(Timex.now(), days: -1)

    target_list
    |> Enum.map(fn slug ->
      {:ok, contract, _token_decimals} = Project.contract_info_by_slug(slug)
      current_daa = realtime_active_addresses(contract)
      average_daa = average_active_addresses(contract, from, to)

      {slug, {current_daa, average_daa}}
    end)
  end

  defp realtime_active_addresses(contract) do
    Cache.get_or_store("daa_#{contract}_current", fn ->
      case DailyActiveAddresses.realtime_active_addresses(contract) do
        {:ok, [{_, result}]} ->
          result

        _ ->
          {:error, :nodata}
      end
    end)
    |> case do
      {:error, _} -> 0
      result -> result
    end
  end

  defp average_active_addresses(contract, from, to) do
    Cache.get_or_store("daa_#{contract}_current", fn ->
      case DailyActiveAddresses.average_active_addresses(contract, from, to) do
        {:ok, [{_, result}]} ->
          result

        _ ->
          {:error, :nodata}
      end
    end)
    |> case do
      {:error, _} -> 0
      result -> result
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

    defp payload(slug, time_window, current_daa, average_daa) do
      project = Project.by_slug(slug)

      """
      **#{project.name}**'s Daily Active Addresses has gone up by **#{
        percent_change(average_daa, current_daa)
      }%** for the last 1 day.
      Average Daily Active Addresses for last **#{
        Sanbase.DateTimeUtils.compound_duration_to_text(time_window)
      }**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHCL price chart for the past 90 days](#{
        chart_url(project, :daily_active_addresses)
      })
      """
    end
  end
end
