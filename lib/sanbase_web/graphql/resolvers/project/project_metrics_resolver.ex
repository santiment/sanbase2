defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  require Logger

  alias Sanbase.Model.Project
  alias Sanbase.Metric

  def available_metrics(%Project{slug: slug}, _args, _resolution) do
    Metric.available_metrics_for_slug(slug)
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, _resolution) do
    Metric.available_timeseries_metrics_for_slug(slug)
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, _resolution) do
    Metric.available_histogram_metrics_for_slug(slug)
  end
end
