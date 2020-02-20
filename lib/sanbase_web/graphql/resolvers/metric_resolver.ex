defmodule SanbaseWeb.Graphql.Resolvers.MetricResolver do
  import SanbaseWeb.Graphql.Helpers.Utils,
    only: [calibrate_interval: 8, calibrate_incomplete_data_params: 5]

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

  def available_since(_root, %{slug: slug}, %{source: %{metric: metric}}),
    do: Metric.first_datetime(metric, slug)

  def last_datetime_computed_at(_root, %{slug: slug}, %{source: %{metric: metric}}),
    do: Metric.last_datetime_computed_at(metric, slug)

  def timeseries_data(
        _root,
        %{slug: slug, from: from, to: to, interval: interval} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)
    aggregation = Map.get(args, :aggregation, nil)

    with {:ok, from, to, interval} <-
           calibrate_interval(Metric, metric, slug, from, to, interval, 86_400, @datapoints),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <-
           Metric.timeseries_data(metric, slug, from, to, interval, aggregation) do
      {:ok, result |> Enum.reject(&is_nil/1)}
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, slug, error)}
    end
  end

  def aggregated_timeseries_data(
        _root,
        %{slug: slug, from: from, to: to} = args,
        %{source: %{metric: metric}}
      ) do
    include_incomplete_data = Map.get(args, :include_incomplete_data, false)
    aggregation = Map.get(args, :aggregation, nil)

    with {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, result} <- Metric.aggregated_timeseries_data(metric, slug, from, to, aggregation) do
      # This requires internal rework - all aggregated_timeseries_data queries must return the same format
      case result do
        value when is_number(value) ->
          {:ok, value}

        [%{slug: ^slug, value: value}] ->
          {:ok, value}

        %{^slug => value} ->
          {:ok, value}

        _ ->
          {:ok, nil}
      end
    else
      {:error, error} ->
        {:error, handle_graphql_error(metric, slug, error)}
    end
  end

  def histogram_data(
        _root,
        %{slug: slug, from: from, to: to, interval: interval, limit: limit},
        %{source: %{metric: metric}}
      ) do
    case Metric.histogram_data(metric, slug, from, to, interval, limit) do
      {:ok, %{labels: labels, values: values}} ->
        {:ok,
         %{
           labels: labels,
           values: %{data: values}
         }}

      {:error, error} ->
        {:error, handle_graphql_error(metric, slug, error)}
    end
  end
end
