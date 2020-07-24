defmodule Sanbase.Signal.Trigger.DailyActiveAddressesSettings do
  @moduledoc ~s"""
  Signals based on the unique number of daily active addresses.

  The signal supports the following operations:
  1. Daily Active Addresses get over or under a given number
  2. Daily Active Addresses change by a given percent compared to the average
     number of daily active addresses over a given time window
  """
  @metric_module Application.compile_env(:sanbase, :metric_module)

  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_days: 1, interval_to_str: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project

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

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  def get_data(%__MODULE__{filtered_target: %{list: target_list}} = settings)
      when is_list(target_list) do
    time_window_in_days = Enum.max([str_to_days(settings.time_window), 1])
    # Ensure there are enough data points in the interval. The not needed
    # ones are ignored
    from = Timex.shift(Timex.now(), days: -(3 * time_window_in_days))
    to = Timex.now()

    target_list
    |> Enum.map(fn slug ->
      case fetch_24h_active_addersses(slug, from, to, "1d") do
        {:ok, result} ->
          {slug, Enum.take(result, -2)}

        _ ->
          nil
      end
    end)
    |> Enum.reject(&is_nil/1)
  end

  defp fetch_24h_active_addersses(slug, from, to, interval) do
    cache_key =
      {__MODULE__, :fetch_24h_active_addersses, slug, round_datetime(from, 300),
       round_datetime(to, 300), interval}
      |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store(cache_key, fn ->
      case @metric_module.timeseries_data(
             "active_addresses_24h",
             %{slug: slug},
             from,
             to,
             interval,
             aggregation: :last
           ) do
        {:ok, result} -> result
        _ -> []
      end
    end)
  end

  defimpl Sanbase.Signal.Settings, for: DailyActiveAddressesSettings do
    alias Sanbase.Signal.{ResultBuilder, OperationText}

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
      ResultBuilder.build(data, settings, &template_kv/2, value_key: :value)
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
      project = Project.by_slug(slug)
      interval = interval_to_str(settings.time_window)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {curr_value_template, curr_value_kv} =
        OperationText.current_value(values, settings.operation)

      kv =
        %{
          type: DailyActiveAddressesSettings.type(),
          operation: settings.operation,
          project_name: project.name,
          project_ticker: project.ticker,
          project_slug: project.slug,
          average_value: values.previous_average,
          interval: interval
        }
        |> Map.merge(operation_kv)
        |> Map.merge(curr_value_kv)

      template = """
       🔔 \#{{project_ticker}} | **{{project_name}}**'s Active Addresses for the past 24 hours #{
        operation_template
      }.
      #{curr_value_template}.

      Average 24 hours Active Addresses for last **{{interval}}*: **{{average_value}}**.
      """

      {template, kv}
    end
  end
end
