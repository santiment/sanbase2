defmodule Sanbase.Signal.Trigger.MetricTriggerSettings do
  @moduledoc ~s"""
  A signal based on the V2 ClickHouse metrics.

  The metric we're following is configured via the 'metric' parameter
  """
  use Vex.Struct

  import Sanbase.{Validation, Signal.Validation}
  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils

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

  def post_create_process(_trigger), do: :nochange
  def post_update_process(_trigger), do: :nochange

  @doc ~s"""
  Return a list of the `settings.metric` values for the necessary time range
  """
  @spec get_data(MetricTriggerSettings.t()) :: list(Metric.metric_result())
  def get_data(%__MODULE__{} = settings) do
    %{time_window: time_window} = settings

    %{metric: metric, filtered_target: %{list: target_list, type: type}} = settings

    target_list
    |> Enum.map(fn identifier ->
      {identifier, fetch_metric(metric, %{type => identifier}, time_window)}
    end)
    |> Enum.reject(fn
      {_, {:error, _}} -> true
      {_, nil} -> true
      _ -> false
    end)
  end

  defguard is_proper_metric_data(data)
           when is_number(data) or (is_map(data) and map_size(data) > 0)

  def fetch_metric(metric, selector, time_window) do
    cache_key =
      {:metric_signal, metric, selector, time_window, round_datetime(Timex.now(), 300)}
      |> Sanbase.Cache.hash()

    interval_seconds = str_to_sec(time_window)
    now = Timex.now()

    first = Timex.shift(now, seconds: -2 * interval_seconds)
    middle = Timex.shift(now, seconds: -interval_seconds)
    last = now

    # NOTE: Rework when the aggregated_timeseries_data function
    # starts to return the result in the same format
    to_value = fn
      %{} = map -> Map.values(map) |> List.first()
      [%{} = map] -> Map.values(map) |> List.first()
      value -> value
    end

    Cache.get_or_store(cache_key, fn ->
      with {:ok, data1} when is_proper_metric_data(data1) <-
             Metric.aggregated_timeseries_data(metric, selector, first, middle),
           {:ok, data2} when is_proper_metric_data(data2) <-
             Metric.aggregated_timeseries_data(metric, selector, middle, last),
           value1 when not is_nil(value1) <- to_value.(data1),
           value2 when not is_nil(value2) <- to_value.(data2) do
        [%{datetime: first, value: value1}, %{datetime: middle, value: value2}]
      else
        _ -> {:error, "Cannot fetch #{metric} for #{inspect(selector)}"}
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
      🔔 The search term '#{text}''s {{metric_human_readable_name}} #{operation_template}.
      #{curr_value_template}.
      """

      {template, kv}
    end

    defp template_kv(values, settings) do
      %{identifier: slug} = values
      project = Project.by_slug(slug)

      opts =
        if String.contains?(settings.metric, "price_usd"),
          do: [special_symbol: "$", value_transform: &Sanbase.Math.round_float/1],
          else: []

      {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

      {operation_template, operation_kv} =
        OperationText.to_template_kv(values, settings.operation, opts)

      {curr_value_template, curr_value_kv} =
        OperationText.current_value(values, settings.operation, opts)

      kv =
        %{
          type: MetricTriggerSettings.type(),
          operation: settings.operation,
          project_name: project.name,
          project_slug: project.slug,
          project_ticker: project.ticker,
          metric: settings.metric,
          metric_human_readable_name: human_readable_name
        }
        |> Map.merge(operation_kv)
        |> Map.merge(curr_value_kv)

      template = """
      🔔 \#{{project_ticker}} | **{{project_name}}**'s {{metric_human_readable_name}} #{
        operation_template
      }.
      #{curr_value_template}.
      """

      {template, kv}
    end
  end
end
