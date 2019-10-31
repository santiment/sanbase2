defmodule Sanbase.Signal.Trigger.MetricTriggerSettings do
  @moduledoc ~s"""
  A signal based on the V2 ClickHouse metrics.

  The metric we're following is configured via the 'metric' parameter
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils, only: [round_datetime: 2, str_to_days: 1]

  alias __MODULE__
  alias Sanbase.Signal.Type
  alias Sanbase.Model.Project
  alias Sanbase.Metric
  alias Sanbase.Signal.Evaluator.Cache

  @derive {Jason.Encoder, except: [:filtered_target, :payload, :triggered?]}
  @trigger_type "metric_signal"
  @enforce_keys [:type, :metric, :target, :channel, :operation]
  defstruct type: @trigger_type,
            metric: nil,
            target: nil,
            channel: nil,
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
          channel: Type.channel(),
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
    |> Enum.map(fn slug -> {slug, fetch_metric(metric, slug, from, to, interval)} end)
    |> Enum.reject(&is_nil/1)
  end

  defp get_timeseries_params(settings) do
    %{time_window: time_window} = settings

    time_window_in_days = Enum.max([str_to_days(time_window), 1])
    to = Timex.now()
    # Ensure there are enough data points in the interval. The not needed
    # ones are ignored    from = Timex.shift(to, days: -(3 * time_window_in_days))
    from = Timex.shift(to, days: -(3 * time_window_in_days))

    {from, to, time_window}
  end

  defp fetch_metric(metric, slug, from, to, interval) do
    cache_key =
      {:metric_signal, metric, slug, round_datetime(from, 300), round_datetime(to, 300), interval}
      |> :erlang.phash2()

    Cache.get_or_store(cache_key, fn ->
      case Metric.timeseries_data(metric, slug, from, to, interval) do
        {:ok, [_ | _] = result} -> result
        _ -> nil
      end
    end)
  end

  defimpl Sanbase.Signal.Settings, for: MetricTriggerSettings do
    alias Sanbase.Signal.Trigger.MetricTriggerSettings
    alias Sanbase.Signal.{OperationText, ResultBuilder, Trigger.MetricTriggerSettings}

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
      ResultBuilder.build(data, settings, &payload/2)
    end

    def cache_key(%MetricTriggerSettings{} = settings) do
      construct_cache_key([
        settings.type,
        settings.target,
        settings.metric,
        settings.time_window,
        settings.operation
      ])
    end

    def payload(values, settings) do
      %{slug: slug} = values

      project = Project.by_slug(slug)
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

      """
      **#{project.name}**'s #{human_readable_name} #{
        OperationText.to_text(values, settings.operation)
      }**.
      More info here: #{Project.sanbase_link(project)}

      ![#{human_readable_name} & OHLC for the past 90 days](#{
        chart_url(project, {:metric, settings.metric})
      })
      """
    end
  end
end
