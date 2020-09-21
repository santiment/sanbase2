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
  @ttl 3600
  @refresh_time_delta 1200
  @refresh_time_max_offset 600

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

  def aggregated_timeseries_data(%Project{slug: slug}, %{metric: metric} = args, %{
        context: %{loader: loader}
      }) do
    case Metric.has_metric?(metric) do
      true ->
        %{from: from, to: to} = args
        include_incomplete_data = Map.get(args, :include_incomplete_data, false)

        {:ok, from, to} =
          calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to)

        from = from |> Sanbase.DateTimeUtils.round_datetime(300)
        to = to |> Sanbase.DateTimeUtils.round_datetime(300)
        opts = selector_args_to_opts(args)

        data = %{
          slug: slug,
          metric: metric,
          selector: {metric, from, to, opts}
        }

        loader
        |> Dataloader.load(SanbaseDataloader, :aggregated_metric, data)
        |> on_load(&aggregated_metric_from_loader(&1, data))

      {:error, error} ->
        {:error, error}
    end
  end

  # Private functions

  defp aggregated_metric_from_loader(loader, data) do
    %{selector: selector, slug: slug, metric: metric} = data

    loader
    |> Dataloader.get(SanbaseDataloader, :aggregated_metric, selector)
    |> case do
      map when is_map(map) ->
        case Map.fetch(map, slug) do
          {:ok, value} ->
            {:ok, value}

          :error ->
            cache_key =
              {__MODULE__, :available_slugs_for_metric, metric}
              |> Sanbase.Cache.hash()

            {:ok, slugs_for_metric} =
              Sanbase.Cache.get_or_store({cache_key, 1800}, fn ->
                Metric.available_slugs(metric)
              end)

            case slug in slugs_for_metric do
              true -> {:nocache, {:ok, nil}}
              false -> {:ok, nil}
            end
        end

      _ ->
        {:nocache, {:ok, nil}}
    end
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
        RehydratingCache.register_function(fun, cache_key, @ttl, refresh_time_delta, description)

        maybe_register_and_get(cache_key, fun, slug, query, attempts - 1)

      {:error, :timeout} ->
        # Recursively call itself. This is guaranteed to not continue forever
        # as the graphql request will timeout at some point and stop the recursion
        maybe_register_and_get(cache_key, fun, slug, query, attempts - 1)
    end
  end
end
