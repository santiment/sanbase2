defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  import Sanbase.Utils.ErrorHandling, only: [maybe_handle_graphql_error: 2]

  alias Sanbase.Model.Project
  alias Sanbase.Metric
  alias Sanbase.Cache.RehydratingCache

  require Logger
  @ttl 3600
  @refresh_time_delta 600
  @refresh_time_max_offset 120

  def available_metrics(%Project{slug: slug}, _args, _resolution) do
    cache_key = {__MODULE__, :available_metrics, slug} |> :erlang.phash2()
    fun = fn -> Metric.available_metrics_for_slug(slug) end

    maybe_register_and_get(cache_key, fun, slug)
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, _resolution) do
    cache_key = {__MODULE__, :available_timeseries_metrics, slug} |> :erlang.phash2()
    fun = fn -> Metric.available_timeseries_metrics_for_slug(slug) end
    maybe_register_and_get(cache_key, fun, slug)
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, _resolution) do
    cache_key = {__MODULE__, :available_histogram_metrics, slug} |> :erlang.phash2()
    fun = fn -> Metric.available_histogram_metrics_for_slug(slug) end
    maybe_register_and_get(cache_key, fun, slug)
  end

  # Get the available metrics from the rehydrating cache. If the function for computing it
  # is not register - register it and get the result after that.z
  defp maybe_register_and_get(cache_key, fun, slug) do
    case RehydratingCache.get(cache_key) do
      {:error, :not_registered} ->
        refresh_time_delta = @refresh_time_delta + :rand.uniform(@refresh_time_max_offset)
        RehydratingCache.register_function(fun, cache_key, @ttl, refresh_time_delta)

        RehydratingCache.get(cache_key)
        |> maybe_handle_graphql_error(&generate_error_message(&1, slug))

      {:ok, value} ->
        {:ok, value}
    end
  end

  defp generate_error_message(_error, slug), do: "Cannot fetch available metrics for #{slug}"
end
