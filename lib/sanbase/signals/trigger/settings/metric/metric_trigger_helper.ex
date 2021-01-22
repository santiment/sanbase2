defmodule Sanbase.Signal.Trigger.MetricTriggerHelper do
  @moduledoc """
  Module that holds the common functionality for the metric signals
  """

  import Sanbase.Signal.Utils
  import Sanbase.DateTimeUtils

  alias Sanbase.Cache
  alias Sanbase.Metric

  alias Sanbase.Signal.{
    OperationText,
    ResultBuilder
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

  # Private functions

  # Return a list of the `settings.metric` values for the necessary time range

  defguard is_proper_metric_data(data)
           when is_number(data) or (is_map(data) and map_size(data) > 0)

  defp fetch_metric(metric, selector, time_window) do
    cache_key =
      {:metric_signal, metric, selector, time_window, round_datetime(Timex.now(), 300)}
      |> Sanbase.Cache.hash()

    interval_seconds = str_to_sec(time_window)
    now = Timex.now()

    first = Timex.shift(now, seconds: -2 * interval_seconds)
    middle = Timex.shift(now, seconds: -interval_seconds)
    last = now

    to_value = fn
      %{} = map -> Map.values(map) |> List.first()
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
