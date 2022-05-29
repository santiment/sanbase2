defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]
  import Absinthe.Resolution.Helpers

  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  alias Sanbase.Model.Project
  alias Sanbase.Metric
  alias Sanbase.Cache.RehydratingCache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  require Logger
  @ttl 2700
  @refresh_time_delta 1800
  @refresh_time_max_offset 900

  def available_metrics(%Project{slug: slug}, _args, _resolution) do
    query = :available_metrics
    cache_key = {__MODULE__, query, slug} |> Sanbase.Cache.hash()
    fun = fn -> Metric.available_metrics_for_slug(%{slug: slug}) end

    maybe_register_and_get(cache_key, fun, slug, query)
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, _resolution) do
    query = :available_timeseries_metrics
    cache_key = {__MODULE__, query, slug} |> Sanbase.Cache.hash()
    fun = fn -> Metric.available_timeseries_metrics_for_slug(%{slug: slug}) end

    maybe_register_and_get(cache_key, fun, slug, query)
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, _resolution) do
    query = :available_histogram_metrics
    cache_key = {__MODULE__, query, slug} |> Sanbase.Cache.hash()
    fun = fn -> Metric.available_histogram_metrics_for_slug(%{slug: slug}) end
    maybe_register_and_get(cache_key, fun, slug, query)
  end

  def available_table_metrics(%Project{slug: slug}, _args, _resolution) do
    query = :available_table_metrics
    cache_key = {__MODULE__, query, slug} |> Sanbase.Cache.hash()
    fun = fn -> Metric.available_table_metrics_for_slug(%{slug: slug}) end
    maybe_register_and_get(cache_key, fun, slug, query)
  end

  def aggregated_timeseries_data(
        %Project{slug: slug},
        %{from: from, to: to, metric: metric} = args,
        %{context: %{loader: loader}}
      ) do
    with true <- Metric.has_metric?(metric),
         true <- Metric.is_not_deprecated?(metric),
         include_incomplete_data = Map.get(args, :include_incomplete_data, false),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to) do
      from = from |> DateTime.truncate(:second)
      to = to |> DateTime.truncate(:second)
      {:ok, opts} = selector_args_to_opts(args)

      data = %{
        slug: slug,
        metric: metric,
        opts: opts,
        selector: {metric, from, to, opts}
      }

      loader
      |> Dataloader.load(SanbaseDataloader, :aggregated_metric, data)
      |> on_load(&aggregated_metric_from_loader(&1, data))
    end
  end

  # Private functions

  defp aggregated_metric_from_loader(loader, data) do
    %{selector: selector, slug: slug, metric: metric} = data

    loader
    |> Dataloader.get(SanbaseDataloader, :aggregated_metric, selector)
    |> case do
      map when is_map(map) ->
        aggregated_metric_from_loader_map(map, slug, metric, data[:opts])

      _ ->
        {:nocache, {:ok, nil}}
    end
  end

  defp aggregated_metric_from_loader_map(map, slug, metric, opts) do
    case Map.fetch(map, slug) do
      {:ok, value} ->
        {:ok, value}

      :error ->
        {:ok, slugs_for_metric} = available_slugs_for_metric(metric, opts)

        # Determine whether the value is missing because it failed to compute or
        # because the metric is not available for the given slug. In the first case
        # return a :nocache tuple so an attempt to compute it is made on the next call
        case slug in slugs_for_metric do
          true -> {:nocache, {:ok, nil}}
          false -> {:ok, nil}
        end
    end
  end

  defp available_slugs_for_metric(metric, opts) do
    cache_key =
      {__MODULE__, :available_slugs_for_metric, metric, opts}
      |> Sanbase.Cache.hash()

    Sanbase.Cache.get_or_store({cache_key, 600}, fn ->
      Metric.available_slugs(metric, opts)
    end)
  end

  # Get the available metrics from the rehydrating cache. If the function for computing it
  # is not register - register it and get the result after that.
  # It can make 5 attempts with 5 seconds timeout, after which it returns an error
  defp maybe_register_and_get(cache_key, fun, slug, query, attempts \\ 5)

  defp maybe_register_and_get(_cache_key, _fun, slug, query, 0) do
    {:error, handle_graphql_error(query, slug, "timeout")}
  end

  defp maybe_register_and_get(cache_key, fun, slug, query, attempts) do
    case RehydratingCache.get(cache_key, 5_000, return_nocache: true) do
      {:nocache, {:ok, value}} ->
        {:nocache, {:ok, value}}

      {:ok, value} ->
        {:ok, value}

      {:error, :not_registered} ->
        refresh_time_delta = @refresh_time_delta + :rand.uniform(@refresh_time_max_offset)

        description = "#{query} for #{slug} from project metrics resolver"

        RehydratingCache.register_function(
          fun,
          cache_key,
          @ttl,
          refresh_time_delta,
          description
        )

        maybe_register_and_get(cache_key, fun, slug, query, attempts - 1)

      {:error, :timeout} ->
        # Recursively call itself. This is guaranteed to not continue forever
        # as the graphql request will timeout at some point and stop the recursion
        maybe_register_and_get(cache_key, fun, slug, query, attempts - 1)
    end
  end
end
