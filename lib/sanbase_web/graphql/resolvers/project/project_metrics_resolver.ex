defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Metric

  def available_metrics(%Project{slug: slug}, _args, _resolution) do
    case Sanbase.Cache.get_or_store(
           {:metric_available_slugs_mapset, 600},
           fn -> Metric.available_slugs_mapset() end
         ) do
      {:ok, list} ->
        if slug in list, do: {:ok, Metric.available_metrics()}, else: {:ok, []}

      {:error, error} ->
        {:error, error}
    end
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, _resolution) do
    case Sanbase.Cache.get_or_store(
           {:metric_available_slugs_mapset, 600},
           fn -> Metric.available_slugs_mapset() end
         ) do
      {:ok, list} ->
        if slug in list, do: {:ok, Metric.available_timeseries_metrics()}, else: {:ok, []}

      {:error, error} ->
        {:error, error}
    end
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, _resolution) do
    case Sanbase.Cache.get_or_store(
           {:metric_available_slugs_mapset, 600},
           fn -> Metric.available_slugs_mapset() end
         ) do
      {:ok, list} ->
        if slug in list, do: {:ok, Metric.available_histogram_metrics()}, else: {:ok, []}

      {:error, error} ->
        {:error, error}
    end
  end
end
