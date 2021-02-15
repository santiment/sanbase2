defmodule Sanbase.Alert.Trigger.MetricTriggerHelper do
  @moduledoc """
  Module that holds the common functionality for the metric alerts
  """

  import Sanbase.Alert.Utils
  import Sanbase.DateTimeUtils

  alias Sanbase.Cache
  alias Sanbase.Metric

  alias Sanbase.Alert.{
    OperationText,
    ResultBuilder
  }

  alias Sanbase.Alert.Trigger.{
    MetricTriggerSettings,
    DailyMetricTriggerSettings
  }

  def triggered?(%{triggered?: triggered?}), do: triggered?

  def cache_key(%{} = settings) do
    construct_cache_key([
      settings.type,
      settings.target,
      settings.metric,
      settings.time_window,
      settings.operation
    ])
  end

  def evaluate(%{} = settings, _trigger) do
    case get_data(settings) do
      data when is_list(data) and data != [] ->
        build_result(data, settings)

      _ ->
        %{settings | triggered?: false}
    end
  end

  def get_data(%{} = settings) do
    %{filtered_target: %{list: target_list, type: type}} = settings

    target_list
    |> Enum.map(fn identifier ->
      {identifier, fetch_metric(%{type => identifier}, settings)}
    end)
    |> Enum.reject(fn
      {_, {:error, _}} -> true
      {_, nil} -> true
      _ -> false
    end)
  end

  # Private functions

  # Return a list of the `settings.metric` values for the necessary time range

  defguard is_proper_metric_data(data)
           when is_number(data) or (is_map(data) and map_size(data) > 0)

  defp fetch_metric(selector, settings) do
    %{metric: metric, time_window: time_window} = settings

    cache_key =
      {:metric_alert, metric, selector, time_window, round_datetime(Timex.now())}
      |> Sanbase.Cache.hash()

    %{
      first_start: first_start,
      first_end: first_end,
      second_start: second_start,
      second_end: second_end
    } = timerange_params(settings)

    to_value = fn
      %{} = map -> Map.values(map) |> List.first()
      value -> value
    end

    Cache.get_or_store(cache_key, fn ->
      with {:ok, data1} when is_proper_metric_data(data1) <-
             Metric.aggregated_timeseries_data(metric, selector, first_start, first_end),
           {:ok, data2} when is_proper_metric_data(data2) <-
             Metric.aggregated_timeseries_data(metric, selector, second_start, second_end),
           value1 when not is_nil(value1) <- to_value.(data1),
           value2 when not is_nil(value2) <- to_value.(data2) do
        [%{datetime: first_start, value: value1}, %{datetime: second_start, value: value2}]
      else
        _ -> {:error, "Cannot fetch #{metric} for #{inspect(selector)}"}
      end
    end)
  end

  defp timerange_params(%MetricTriggerSettings{} = settings) do
    interval_seconds = str_to_sec(settings.time_window)
    now = Timex.now()

    %{
      first_start: Timex.shift(now, seconds: -2 * interval_seconds),
      first_end: Timex.shift(now, seconds: -interval_seconds),
      second_start: Timex.shift(now, seconds: -interval_seconds),
      second_end: now
    }
  end

  defp timerange_params(%DailyMetricTriggerSettings{} = settings) do
    # Because the daily metrics use `Date` type in the column and check with
    # >= and <=, in order to fetch exactly one day of data, the `from` param
    # must start at 00:00:00Z and the `to` param must end at 23:59:59Z
    interval_seconds = str_to_sec(settings.time_window)
    now = Timex.now() |> Timex.beginning_of_day() |> Timex.shift(seconds: -1)

    %{
      first_start: Timex.shift(now, seconds: -2 * interval_seconds + 1),
      first_end: Timex.shift(now, seconds: -interval_seconds),
      second_start: Timex.shift(now, seconds: -interval_seconds + 1),
      second_end: now
    }
  end

  defp build_result(data, %{} = settings) do
    ResultBuilder.build(data, settings, &template_kv/2)
  end

  defp template_kv(values, %{target: %{text: _}} = settings) do
    %{identifier: text} = values

    {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

    {operation_template, operation_kv} = OperationText.to_template_kv(values, settings.operation)

    {curr_value_template, curr_value_kv} = OperationText.current_value(values)

    kv =
      %{
        type: settings.type,
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
    project = Sanbase.Model.Project.by_slug(slug)

    opts =
      if String.contains?(settings.metric, "price_usd"),
        do: [special_symbol: "$", value_transform: &Sanbase.Math.round_float/1],
        else: []

    {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

    {operation_template, operation_kv} =
      OperationText.to_template_kv(values, settings.operation, opts)

    {curr_value_template, curr_value_kv} = OperationText.current_value(values, opts)

    {details_template, details_kv} = OperationText.details(:metric, settings)

    kv =
      %{
        type: settings.type,
        operation: settings.operation,
        project_name: project.name,
        project_slug: project.slug,
        project_ticker: project.ticker,
        metric: settings.metric,
        metric_human_readable_name: human_readable_name
      }
      |> Map.merge(operation_kv)
      |> Map.merge(curr_value_kv)
      |> Map.merge(details_kv)

    template = """
    🔔 \#{{project_ticker}} | **{{project_name}}**'s {{metric_human_readable_name}} #{
      operation_template
    }.
    #{curr_value_template}.

    #{details_template}
    """

    {template, kv}
  end
end
