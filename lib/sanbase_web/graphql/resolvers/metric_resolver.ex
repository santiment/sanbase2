defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils

  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3, handle_graphql_error: 4]

  alias Sanbase.Metric
  alias Sanbase.Billing.Plan.Restrictions

  require Logger

  @datapoints 300

  def get_metric(_root, %{metric: metric}, _resolution) do
    case Metric.has_metric?(metric) do
      true -> {:ok, %{metric: metric}}
      {:error, error} -> {:error, error}
    end
  end

  def get_available_metrics(_root, _args, _resolution), do: {:ok, Metric.available_metrics()}

  def get_available_slugs(_root, _args, %{source: %{metric: metric}}),
    do: Metric.available_slugs(metric)

  def get_metadata(%{}, _args, %{source: %{metric: metric}} = resolution) do
    %{context: %{product_id: product_id, auth: %{subscription: subscription}}} = resolution

    case Metric.metadata(metric) do
      {:ok, metadata} ->
        access_restrictions = Restrictions.get({:metric, metric}, subscription, product_id)
        {:ok, Map.merge(access_restrictions, metadata)}

      {:error, error} ->
        {:error, handle_graphql_error("metadata", metric, error, description: "metric")}
    end
  end

  def available_since(_root, args, %{source: %{metric: metric}}),
    do: Metric.first_datetime(metric, to_selector(args))

  def last_datetime_computed_at(_root, args, %{source: %{metric: metric}}),
    do: Metric.last_datetime_computed_at(metric, to_selector(args))

  def timeseries_data(
        _root,
        %{from: from, to: to, interval: interval} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)

    transform =
      Map.get(args, :transform, %{type: "none"}) |> Map.update!(:type, &Inflex.underscore/1)

    aggregation = Map.get(args, :aggregation, nil)
    selector = to_selector(args)
    metric = maybe_replace_metric(metric, selector)

    with {:ok, from, to, interval} <-
           calibrate_interval(Metric, metric, selector, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, from} <-
           calibrate_transform_params(transform, from, to, interval),
         {:ok, result} <-
           Metric.timeseries_data(metric, selector, from, to, interval, aggregation),
         {:ok, result} <- apply_transform(transform, result),
         {:ok, result} <- fit_from_datetime(result, args) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, selector, error)}
    end
  end

  # gold and s-and-p-500 are present only in the intrday metrics table, not in asset_prices
  defp maybe_replace_metric("price_usd", %{slug: slug}) when slug in ["gold", "s-and-p-500"],
    do: "price_usd_5m"

  defp maybe_replace_metric(metric, _selector), do: metric

  defp calibrate_transform_params(%{type: "none"}, from, _to, _interval),
    do: {:ok, from}

  defp calibrate_transform_params(
         %{type: "moving_average", moving_average_base: base},
         from,
         _to,
         interval
       ) do
    shift_by_sec = base * Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  defp calibrate_transform_params(%{type: "changes"}, from, _to, interval) do
    shift_by_sec = Sanbase.DateTimeUtils.str_to_sec(interval)
    from = Timex.shift(from, seconds: -shift_by_sec)
    {:ok, from}
  end

  defp apply_transform(%{type: "none"}, data), do: {:ok, data}

  defp apply_transform(%{type: "moving_average", moving_average_base: base}, data) do
    Sanbase.Math.simple_moving_average(data, base, value_key: :value)
  end

  defp apply_transform(%{type: "changes"}, data) do
    result =
      Stream.chunk_every(data, 2, 1, :discard)
      |> Enum.map(fn [%{value: previous}, %{value: next, datetime: datetime}] ->
        %{
          datetime: datetime,
          value: next - previous
        }
      end)

    {:ok, result}
  end

  def aggregated_timeseries_data(
        _root,
        %{from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)
    aggregation = Map.get(args, :aggregation, nil)

    with {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <-
           Metric.aggregated_timeseries_data(metric, to_selector(args), from, to, aggregation) do
      # This requires internal rework - all aggregated_timeseries_data queries must return the same format
      case result do
        value when is_number(value) ->
          {:ok, value}

        [%{value: value}] ->
          {:ok, value}

        %{} = map ->
          value = Map.values(map) |> hd
          {:ok, value}

        _ ->
          {:ok, nil}
      end
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, to_selector(args), error)}
    end
  end

  def histogram_data(
        _root,
        %{from: from, to: to, interval: interval, limit: limit} = args,
        %{source: %{metric: metric}}
      ) do
    case Metric.histogram_data(metric, to_selector(args), from, to, interval, limit) do
      {:ok, data} ->
        {:ok, %{values: %{data: data}}}

      {:error, error} ->
        {:error, handle_graphql_error(metric, to_selector(args), error)}
    end
  end

  defp to_selector(%{slug: slug}), do: %{slug: slug}
  defp to_selector(%{word: word}), do: %{word: word}
  defp to_selector(%{selector: %{} = selector}), do: selector
end
