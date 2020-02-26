defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]
  import SanbaseWeb.Graphql.Helpers.Async, only: [async: 1]

  alias Sanbase.Model.Project
  alias Sanbase.Metric
  alias Sanbase.Cache.RehydratingCache

  require Logger
  @ttl 3600
  @refresh_time_delta 600
  @refresh_time_max_offset 120

  def available_metrics(%Project{slug: slug}, _args, _resolution) do
    async(fn ->
      query = :available_metrics
      cache_key = {__MODULE__, query, slug} |> :erlang.phash2()
      fun = fn -> Metric.available_metrics_for_slug(%{slug: slug}) end

      maybe_register_and_get(cache_key, fun, slug, query)
    end)
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, _resolution) do
    async(fn ->
      query = :available_timeseries_metrics
      cache_key = {__MODULE__, query, slug} |> :erlang.phash2()
      fun = fn -> Metric.available_timeseries_metrics_for_slug(%{slug: slug}) end
      maybe_register_and_get(cache_key, fun, slug, query)
    end)
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, _resolution) do
    async(fn ->
      query = :available_histogram_metrics
      cache_key = {__MODULE__, query, slug} |> :erlang.phash2()
      fun = fn -> Metric.available_histogram_metrics_for_slug(%{slug: slug}) end
      maybe_register_and_get(cache_key, fun, slug, query)
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
    case RehydratingCache.get(cache_key, 5_000) do
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
