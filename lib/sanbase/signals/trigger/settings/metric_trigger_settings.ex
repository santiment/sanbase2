defmodule Sanbase.Signal.Trigger.MetricTriggerSettings do
  @moduledoc ~s"""
  A signal based on the V2 ClickHouse metrics.

  The metric we're following is configured via the 'metric' parameter
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_sec: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Clickhouse.Metric
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "metric_signal"
  @enforce_keys [:type, :metric, :target, :channel, :operation]
  defstruct type: @trigger_type,
            metric: nil,
            target: nil,
            channel: nil,
            interval: "1d",
            time_window: "1d",
            operation: nil,
            triggered?: false,
            payload: nil,
            filtered_target: %{list: []}

  validates(:metric, &valid_metric?/1)
  validates(:target, &valid_target?/1)
  validates(:channel, &valid_notification_channel?/1)
  validates(:interval, &valid_time_window?/1)
  validates(:time_window, &valid_time_window?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          metric: Type.metric(),
          target: Type.complex_target(),
          channel: Type.channel(),
          interval: Type.time_window(),
          time_window: Type.time_window(),
          operation: Type.operation(),
          triggered?: boolean(),
          payload: Type.payload(),
          filtered_target: Type.filtered_target()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  @spec get_data(MetricTriggerSettings.t()) :: list(Metric.metric_result())
  def get_data(%__MODULE__{} = settings) do
    {from, to, interval} = get_timeseries_params(settings)

    %{metric: metric, filtered_target: %{list: target_list}} = settings

    target_list
    |> Enum.map(fn slug -> fetch_metric(metric, slug, from, to, interval) end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_timeseries_params(settings) do
    %{interval: interval, time_window: time_window} = settings

    time_window_sec = str_to_sec(time_window)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    {from, to, interval}
  end

  defp fetch_metric(metric, slug, from, to, interval) do
    cache_key =
      {metric, slug, round_datetime(from, 300), round_datetime(to, 300), interval}
      |> :erlang.phash2()

    Cache.get_or_store(cache_key, fn ->
      case Metric.get(metric, slug, from, to, interval) do
        {:ok, [_ | _] = result} -> result
        _ -> nil
      end
    end)
  end

  defimpl Sanbase.Signal.Settings, for: MetricTriggerSettings do
    alias Sanbase.Signal.Trigger.MetricTriggerSettings
    alias Sanbase.Signal.{Operation, OperationText, ResultBuilder, Trigger.MetricTriggerSettings}

    def triggered?(%MetricTriggerSettings{triggered?: triggered}), do: triggered

    @spec evaluate(MetricTriggerSettings.t(), any) :: MetricTriggerSettings.t()
    def evaluate(%MetricTriggerSettings{} = settings, _trigger) do
      case MetricTriggerSettings.get_data(settings) do
        data when is_list(data) and data != [] ->
          build_result(data, settings)

        _ ->
          %MetricTriggerSettings{settings | triggered?: false}
      end
    end

    def build_result(data, %MetricTriggerSettings{} = settings) do
      case Operation.type(settings.operation) do
        :percent -> build_result_percent(data, settings)
        :absolute -> build_result_absolute(data, settings)
      end
    end

    defp build_result_percent(data, settings) do
      ResultBuilder.build_result_percent(data, settings, &payload/4)
    end

    defp build_result_absolute(data, settings) do
      ResultBuilder.build_result_absolute(data, settings, &payload/4)
    end

    def cache_key(%MetricTriggerSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.metric,
        settings.time_window,
        settings.interval,
        settings.operation
      ])
    end

    defp payload(:percent, slug, settings, values) do
      %{current: current_daa, previous_average: average_daa, percent_change: percent_change} =
        values

      project = Project.by_slug(slug)
      interval = Sanbase.DateTimeUtils.interval_to_str(settings.time_window)

      """
      **#{project.name}**'s #{settings.metric} #{
        OperationText.to_text(percent_change, settings.operation)
      }* up to #{current_daa}  compared to the average value for the last #{interval}.
      Average #{settings.metric} for last **#{interval}**: **#{average_daa}**.
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHLC price chart for the past 90 days](#{
        chart_url(project, :daily_active_addresses)
      })
      """
    end

    defp payload(:absolute, slug, settings, %{current: current}) do
      project = Project.by_slug(slug)

      """
      **#{project.name}**'s #{settings.metric} #{
        OperationText.to_text(current, settings.operation)
      }
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHLC price chart for the past 90 days](#{
        chart_url(project, :daily_active_addresses)
      })
      """
    end
  end
end
