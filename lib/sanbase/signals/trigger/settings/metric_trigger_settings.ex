defmodule Sanbase.Signal.Trigger.MetricTriggerSettings do
  @moduledoc ~s"""

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
  @enforce_keys [:type, :target, :metric, :channel, :operation]
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
  validates(:time_window, &valid_time_window?/1)
  validates(:operation, &valid_operation?/1)

  @type t :: %__MODULE__{
          type: Type.trigger_type(),
          metric: Type.metric(),
          target: Type.complex_target(),
          operation: Type.operation(),
          channel: Type.channel(),
          time_window: Type.time_window(),
          triggered?: boolean(),
          payload: Type.payload(),
          filtered_target: Type.filtered_target()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  def get_data(%__MODULE__{} = settings) do
    %{metric: metric, interval: interval, filtered_target: %{list: target_list}} = settings

    time_window_sec = str_to_sec(settings.time_window)
    to = Timex.now()
    from = Timex.shift(to, seconds: -time_window_sec)

    target_list
    |> Enum.map(fn slug -> fetch_metric(metric, slug, from, to, interval) end)
    |> Enum.reject(&is_nil/1)
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
    alias Sanbase.Signal.{Operation, OperationText, Trigger.MetricTriggerSettings}

    import Sanbase.Signal.OperationEvaluation

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

    defp build_result_percent(
           data,
           %MetricTriggerSettings{operation: operation} = settings
         ) do
      payload =
        transform_data_percent(data)
        |> Enum.reduce(%{}, fn {slug, {previous_avg, current, percent_change}}, acc ->
          case operation_triggered?(percent_change, operation) do
            true ->
              Map.put(
                acc,
                slug,
                payload(:percent, slug, settings, {current, previous_avg, percent_change})
              )

            false ->
              acc
          end
        end)

      %MetricTriggerSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    defp build_result_absolute(
           data,
           %MetricTriggerSettings{operation: operation} = settings
         ) do
      payload =
        transform_data_absolute(data)
        |> Enum.reduce(%{}, fn {slug, active_addresses}, acc ->
          case operation_triggered?(active_addresses, operation) do
            true ->
              Map.put(acc, slug, payload(:absolute, slug, settings, active_addresses))

            false ->
              acc
          end
        end)

      %MetricTriggerSettings{
        settings
        | triggered?: payload != %{},
          payload: payload
      }
    end

    defp transform_data_percent(data) do
      Enum.map(data, fn {slug, values} ->
        # current is the last element, previous_list is the list of all other elements
        {current, previous_list} =
          values
          |> Enum.map(& &1.value)
          |> List.pop_at(-1)

        previous_avg =
          previous_list
          |> Sanbase.Math.average(precision: 2)

        {slug, {previous_avg, current, percent_change(previous_avg, current)}}
      end)
    end

    defp transform_data_absolute(data) do
      Enum.map(data, fn {slug, daa} ->
        %{value: last} = List.last(daa)
        {slug, last}
      end)
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

    defp payload(:percent, slug, settings, {current_daa, average_daa, percent_change}) do
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

    defp payload(:absolute, slug, settings, value) do
      project = Project.by_slug(slug)

      """
      **#{project.name}**'s #{settings.metric} #{OperationText.to_text(value, settings.operation)}
      More info here: #{Project.sanbase_link(project)}

      ![Daily Active Addresses chart and OHLC price chart for the past 90 days](#{
        chart_url(project, :daily_active_addresses)
      })
      """
    end
  end
end
