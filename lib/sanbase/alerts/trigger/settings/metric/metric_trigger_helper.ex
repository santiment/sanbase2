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
      {:ok, data} when is_list(data) and data != [] ->
        build_result(data, settings)

      {:error, {:disable_alert, _}} = error ->
        error

      {:error, :target_empty_list} ->
        # There's nothing to be triggered
        {:ok, %{settings | triggered?: false}}

      _ ->
        {:ok, %{settings | triggered?: false}}
    end
  end

  def get_data(%{filtered_target: %{list: []}}) do
    {:error, :target_empty_list}
  end

  def get_data(%{filtered_target: %{list: target_list, type: type}} = settings) do
    # When the target is :text, the target_list always contains 0 or 1 elements.
    # But the social data functions don't know how to work with lists.
    # Handle by rewriting the selector.
    # An alternative would be to rewrite the remove_targets_on_cooldown function in the trigger.ex
    # file, but then the argument `:list` will no longer be list.
    selector =
      if type == :text and length(target_list) == 1 do
        %{text: hd(target_list)}
      else
        %{type => target_list}
      end

    case fetch_metric(selector, settings) do
      {:error, {:disable_alert, _reason}} = error ->
        error

      {:error, _error} = error ->
        error

      {:ok, data} ->
        # The target_list could be a list of many identifiers, i.e. slugs.
        # This unfolding will map this map of slug => value pairs to
        # one element per identifier
        result = unfold_result(data)
        {:ok, result}
    end
  end

  # Private functions

  def unfold_result(data) do
    [
      %{datetime: dt1, value: data1},
      %{datetime: dt2, value: data2}
    ] = data

    Enum.map(data1, fn {k, v} ->
      {k, [%{datetime: dt1, value: v}, %{datetime: dt2, value: Map.get(data2, k)}]}
    end)
    |> Enum.reject(fn {_k, [%{value: v1}, %{value: v2}]} -> is_nil(v1) or is_nil(v2) end)
  end

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

    Cache.get_or_store(cache_key, fn ->
      with {:ok, data1} when is_proper_metric_data(data1) <-
             Metric.aggregated_timeseries_data(metric, selector, first_start, first_end),
           {:ok, data2} when is_proper_metric_data(data2) <-
             Metric.aggregated_timeseries_data(metric, selector, second_start, second_end) do
        {:ok, [%{datetime: first_start, value: data1}, %{datetime: second_start, value: data2}]}
      else
        {:error, error} when is_binary(error) ->
          handle_fetch_metric_error(error, metric, selector)

        _ ->
          {:error, "Cannot fetch #{metric} for #{inspect(selector)}"}
      end
    end)
  end

  defp handle_fetch_metric_error(error_msg, metric, selector) when is_binary(error_msg) do
    if error_msg =~ "not supported, is deprecated or is mistyped" do
      {:error, {:disable_alert, error_msg}}
    else
      {:error, "Cannot fetch #{metric} for #{inspect(selector)}. Reason: #{error_msg}"}
    end
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
        metric_human_readable_name: human_readable_name,
        extra_explanation: settings.extra_explanation
      }
      |> OperationText.merge_kvs(operation_kv)
      |> OperationText.merge_kvs(curr_value_kv)

    template = """
    🔔 The search term '#{text}''s {{metric_human_readable_name}} #{operation_template}.
    #{curr_value_template}.
    #{maybe_add_extra_explanation(settings.extra_explanation)}
    """

    template = settings.template || template

    {template, kv}
  end

  defp template_kv(values, %{target: %{slug: "TOTAL_MARKET"}} = settings) do
    {:ok, human_readable_name} = Sanbase.Metric.human_readable_name(settings.metric)

    {operation_template, operation_kv} = OperationText.to_template_kv(values, settings.operation)

    {curr_value_template, curr_value_kv} = OperationText.current_value(values)

    {details_template, details_kv} = OperationText.details(:metric, settings)

    kv =
      %{
        type: settings.type,
        operation: settings.operation,
        project_slug: "TOTAL_MARKET",
        metric: settings.metric,
        metric_human_readable_name: human_readable_name,
        extra_explanation: settings.extra_explanation
      }
      |> OperationText.merge_kvs(operation_kv)
      |> OperationText.merge_kvs(curr_value_kv)
      |> OperationText.merge_kvs(details_kv)

    template = """
    🔔 The total market's {{metric_human_readable_name}} #{operation_template}* 💥

    #{curr_value_template}
    #{maybe_add_extra_explanation(settings.extra_explanation)}
    #{details_template}
    """

    template = settings.template || template

    {template, kv}
  end

  defp template_kv(values, settings) do
    %{identifier: slug} = values
    project = Sanbase.Project.by_slug(slug)

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
        sanbase_project_link: "https://app.santiment.net/charts?slug=#{project.slug}",
        metric: settings.metric,
        metric_human_readable_name: human_readable_name,
        extra_explanation: settings.extra_explanation
      }
      |> OperationText.merge_kvs(operation_kv)
      |> OperationText.merge_kvs(curr_value_kv)
      |> OperationText.merge_kvs(details_kv)

    template = """
    🔔 [\#{{project_ticker}}]({{sanbase_project_link}}) | *{{project_name}}'s {{metric_human_readable_name}} #{operation_template}* 💥

    #{curr_value_template}
    #{maybe_add_extra_explanation(settings.extra_explanation)}
    #{details_template}
    """

    template = settings.template || template

    {template, kv}
  end

  defp maybe_add_extra_explanation(nil), do: ""
  defp maybe_add_extra_explanation(_), do: "\n🧐 {{extra_explanation}}\n"
end
