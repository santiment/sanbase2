defmodule SanbaseWeb.Graphql.Resolvers.ProjectMetricsResolver do
  import Sanbase.Utils.ErrorHandling, only: [handle_graphql_error: 3]
  import Absinthe.Resolution.Helpers

  import SanbaseWeb.Graphql.Helpers.Utils
  import SanbaseWeb.Graphql.Helpers.CalibrateInterval

  alias Sanbase.Project
  alias Sanbase.Metric
  alias Sanbase.Cache.RehydratingCache
  alias SanbaseWeb.Graphql.SanbaseDataloader

  @ttl 7200
  @refresh_time_delta 1800
  @refresh_time_max_offset 1800

  def available_label_fqns(%Project{slug: slug}, _args, _resolution) do
    Sanbase.Clickhouse.Label.label_fqns_with_asset(slug)
  end

  def available_metrics(%Project{slug: slug}, _args, resolution) do
    # TEMP 02.02.2023: Handle ripple -> xrp rename
    with {:ok, %{slug: slug}} <- Sanbase.Project.Selector.args_to_selector(%{slug: slug}) do
      user_metric_access_level = user_metric_access_level(resolution)
      lookback_days = user_available_metrics_lookback_days(resolution)

      query = :available_metrics

      cache_key =
        {__MODULE__, query, slug, user_metric_access_level, lookback_days}
        |> Sanbase.Cache.hash()

      fun = fn ->
        Metric.available_metrics_for_selector(%{slug: slug},
          user_metric_access_level: user_metric_access_level,
          lookback_days: lookback_days
        )
      end

      maybe_register_and_get(cache_key, fun, slug, query)
    end
  end

  def available_metrics_extended(%Project{} = project, args, resolution) do
    case available_metrics(project, args, resolution) do
      {:ok, metrics} -> {:ok, add_metadata_to_metrics(metrics)}
      {:nocache, {:ok, metrics}} -> {:ok, add_metadata_to_metrics(metrics)}
      {:error, error} -> {:error, error}
    end
  end

  def available_timeseries_metrics(%Project{slug: slug}, _args, resolution) do
    # TEMP 02.02.2023: Handle ripple -> xrp rename
    with {:ok, %{slug: slug}} <- Sanbase.Project.Selector.args_to_selector(%{slug: slug}) do
      user_metric_access_level = user_metric_access_level(resolution)
      lookback_days = user_available_metrics_lookback_days(resolution)

      query = :available_timeseries_metrics

      cache_key =
        {__MODULE__, query, slug, user_metric_access_level, lookback_days}
        |> Sanbase.Cache.hash()

      fun = fn ->
        Metric.available_timeseries_metrics_for_slug(%{slug: slug},
          user_metric_access_level: user_metric_access_level,
          lookback_days: lookback_days
        )
      end

      maybe_register_and_get(cache_key, fun, slug, query)
    end
  end

  def available_histogram_metrics(%Project{slug: slug}, _args, resolution) do
    # TEMP 02.02.2023: Handle ripple -> xrp rename
    with {:ok, %{slug: slug}} <- Sanbase.Project.Selector.args_to_selector(%{slug: slug}) do
      user_metric_access_level = user_metric_access_level(resolution)
      lookback_days = user_available_metrics_lookback_days(resolution)

      query = :available_histogram_metrics

      cache_key =
        {__MODULE__, query, slug, user_metric_access_level, lookback_days}
        |> Sanbase.Cache.hash()

      fun = fn ->
        Metric.available_histogram_metrics_for_slug(%{slug: slug},
          user_metric_access_level: user_metric_access_level,
          lookback_days: lookback_days
        )
      end

      maybe_register_and_get(cache_key, fun, slug, query)
    end
  end

  def available_table_metrics(%Project{slug: slug}, _args, resolution) do
    # TEMP 02.02.2023: Handle ripple -> xrp rename
    with {:ok, %{slug: slug}} <- Sanbase.Project.Selector.args_to_selector(%{slug: slug}) do
      user_metric_access_level = user_metric_access_level(resolution)
      lookback_days = user_available_metrics_lookback_days(resolution)

      query = :available_table_metrics

      cache_key =
        {__MODULE__, query, slug, user_metric_access_level, lookback_days}
        |> Sanbase.Cache.hash()

      fun = fn ->
        Metric.available_table_metrics_for_slug(%{slug: slug},
          user_metric_access_level: user_metric_access_level,
          lookback_days: lookback_days
        )
      end

      maybe_register_and_get(cache_key, fun, slug, query)
    end
  end

  defp user_metric_access_level(resolution) do
    get_in(resolution.context, [:auth, :current_user, Access.key(:metric_access_level)]) ||
      "released"
  end

  defp user_available_metrics_lookback_days(resolution) do
    get_in(resolution.context, [
      :auth,
      :current_user,
      Access.key(:available_metrics_lookback_days)
    ])
  end

  def aggregated_timeseries_data(
        %Project{slug: slug},
        %{from: from, to: to, metric: metric} = args,
        %{context: %{loader: loader}}
      ) do
    only_finalized_data = Map.get(args, :only_finalized_data, false)

    # TEMP 02.02.2023: Handle ripple -> xrp rename
    with {:ok, %{slug: slug}} <- Sanbase.Project.Selector.args_to_selector(%{slug: slug}),
         true <- Metric.has_metric?(metric),
         false <- Metric.hard_deprecated?(metric),
         include_incomplete_data = Map.get(args, :include_incomplete_data, false),
         {:ok, from, to} <-
           calibrate_incomplete_data_params(include_incomplete_data, Metric, metric, from, to),
         {:ok, opts} <- selector_args_to_opts(args),
         opts <- Keyword.put(opts, :only_finalized_data, only_finalized_data) do
      from = DateTime.truncate(from, :second)
      to = DateTime.truncate(to, :second)

      data = %{
        slug: slug,
        metric: metric,
        opts: opts,
        selector: {metric, from, to, opts}
      }

      error_on_data_fetch_fail = Map.get(args, :error_on_data_fetch_fail, false)

      loader
      |> Dataloader.load(SanbaseDataloader, :aggregated_metric, data)
      |> on_load(&aggregated_metric_from_loader(&1, data, error_on_data_fetch_fail))
    end
  end

  # Private functions

  defp aggregated_metric_from_loader(loader, data, error_on_data_fetch_fail) do
    %{selector: selector, slug: slug, metric: metric} = data

    loader
    |> Dataloader.get(SanbaseDataloader, :aggregated_metric, selector)
    |> case do
      map when is_map(map) ->
        aggregated_metric_from_loader_map(map, slug, metric, data[:opts])

      _ignored when error_on_data_fetch_fail == false ->
        {:nocache, {:ok, nil}}

      _ignored when error_on_data_fetch_fail == true ->
        {:error,
         "Failed to fetch aggregatedTimeseriesData for metric #{metric} and asset #{slug}"}
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
  # It can make 5 attempts with 5 seconds timeout, after which it returns an error.
  #
  # In the test environment `:use_rehydrating_cache` defaults to `false` so the resolver
  # takes the synchronous `Sanbase.Cache.get_or_store/2` fallback below. Rationale: the
  # `RehydratingCache` GenServer periodically re-runs every registered closure, and a
  # closure registered inside a `with_mocks` block can outlive that block and re-fire
  # later against real code (e.g. Clickhouse adapters), producing intermittent
  # "could not lookup Ecto repo Sanbase.ClickhouseRepo" warnings in unrelated tests.
  # The supervisor is also not started in the test app boot path — see
  # `Sanbase.Application.Web`. Tests that need to exercise the RC wiring end-to-end flip
  # the flag back to `true` in their `setup` block and start a per-test
  # `RehydratingCache.Supervisor` via `start_supervised!`.
  defp maybe_register_and_get(cache_key, fun, slug, query, attempts \\ 5)

  defp maybe_register_and_get(cache_key, fun, slug, query, attempts) do
    if rehydrating_cache_enabled?() do
      register_and_get_via_rehydrating_cache(cache_key, fun, slug, query, attempts)
    else
      # Synchronous fallback used in test only. `Sanbase.Cache.get_or_store/2` unwraps
      # `{:nocache, {:ok, value}}` to `{:ok, value}`, so full `:nocache` semantics are
      # NOT preserved on this path. Tests that depend on `:nocache` propagation must opt
      # back into the RC path.
      Sanbase.Cache.get_or_store({cache_key, @ttl}, fun)
    end
  end

  defp rehydrating_cache_enabled?() do
    Application.get_env(:sanbase, :use_rehydrating_cache, true)
  end

  defp register_and_get_via_rehydrating_cache(_cache_key, _fun, slug, query, 0) do
    {:error,
     handle_graphql_error(
       query,
       slug,
       "timeout after 5 attempts waiting on RehydratingCache " <>
         "(upstream adapter(s) likely slow — see prior 'slow module' warnings)"
     )}
  end

  defp register_and_get_via_rehydrating_cache(cache_key, fun, slug, query, attempts) do
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

        register_and_get_via_rehydrating_cache(cache_key, fun, slug, query, attempts - 1)

      {:error, :timeout} ->
        # Recursively call itself. This is guaranteed to not continue forever
        # as the graphql request will timeout at some point and stop the recursion
        register_and_get_via_rehydrating_cache(cache_key, fun, slug, query, attempts - 1)
    end
  end

  defp add_metadata_to_metrics(metrics) do
    Enum.map(metrics, fn m ->
      {:ok, m} = Metric.metadata(m)

      m
    end)
  end
end
