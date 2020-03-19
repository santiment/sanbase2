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

  @trigger_type "metric_signal"
  @derive {Jason.Encoder, except: [:filtered_target, :triggered?, :payload, :template_kv]}
  @enforce_keys [:type, :metric, :target, :channel, :operation]
  defstruct type: @trigger_type,
            metric: nil,
            target: nil,
            channel: nil,
            time_window: "1d",
            operation: nil,
            # Private fields, not stored in DB.
            filtered_target: %{list: []},
            triggered?: false,
            payload: %{},
            template_kv: %{}

  validates(:metric, &valid_metric?/1)
  validates(:metric, &valid_5m_min_interval_metric?/1)
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
          # Private fields, not stored in DB.
          filtered_target: Type.filtered_target(),
          triggered?: boolean(),
          payload: Type.payload(),
          template_kv: Type.template_kv()
        }

  @spec type() :: Type.trigger_type()
  def type(), do: @trigger_type

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  @spec get_data(MetricTriggerSettings.t()) :: list(Metric.metric_result())
  def get_data(%__MODULE__{} = settings) do
    {from, to, interval} = get_timeseries_params(settings)

    %{metric: metric, filtered_target: %{list: target_list, type: type}} = settings

    target_list
    |> Enum.map(fn identifier ->
      {identifier, fetch_metric(metric, %{type => identifier}, from, to, interval)}
    end)
    |> Enum.reject(fn
      {_, nil} -> true
      _ -> false
    end)
  end

  defp get_timeseries_params(settings) do
    %{time_window: time_window} = settings

    time_window_in_days = Enum.max([str_to_days(time_window), 1])
    to = Timex.now()
    # Ensure there are enough data points in the interval. The not needed
    # ones are ignored
    from = Timex.shift(to, days: -(3 * time_window_in_days))

    {from, to, time_window}
  end

  defp fetch_metric(metric, selector, from, to, interval) do
    cache_key =
      {:metric_signal, metric, selector, round_datetime(from, 300), round_datetime(to, 300),
       interval}
      |> :erlang.phash2()

    Cache.get_or_store(cache_key, fn ->
      case Metric.timeseries_data(metric, selector, from, to, interval) do
        {:ok, [_ | _] = result} -> result |> Enum.take(-2)
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
      ResultBuilder.build(data, settings, &template_kv/2)
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

    defp template_kv(values, %{target: %{text: _}} = settings) do
      %{identifier: text} = values

      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {curr_value_template, curr_value_kv} =
        OperationText.current_value(values, settings.operation)

      kv =
        %{
          type: MetricTriggerSettings.type(),
          operation: settings.operation,
          search_text: text,
          metric: settings.metric,
          metric_human_readable_name: human_readable_name
        }
        |> Map.merge(operation_kv)
        |> Map.merge(curr_value_kv)

      template = """
      **{{project_name}}**'s {{metric_human_readable_name}} #{operation_template} and #{
        curr_value_template
      }.
      """

      {template, kv}
    end

    defp template_kv(values, settings) do
      %{identifier: slug} = values

      project = Project.by_slug(slug)
      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation)

      {curr_value_template, curr_value_kv} =
        OperationText.current_value(values, settings.operation)

      kv =
        %{
          type: MetricTriggerSettings.type(),
          operation: settings.operation,
          project_name: project.name,
          project_slug: project.slug,
          metric: settings.metric,
          metric_human_readable_name: human_readable_name,
          chart_url: chart_url(project, {:metric, settings.metric})
        }
        |> Map.merge(operation_kv)
        |> Map.merge(curr_value_kv)

      template = """
      **{{project_name}}**'s {{metric_human_readable_name}} #{operation_template} and #{
        curr_value_template
      }.
      More info here: #{Project.sanbase_link(project)}

      ![#{human_readable_name} & OHLC for the past 90 days]({{chart_url}})
      """

      {template, kv}
    end
  end
end
