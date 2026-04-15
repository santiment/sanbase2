defmodule Sanbase.MCP.DataCatalog do
  @moduledoc "Centralized catalog of available metrics and slugs for MCP tools"

  @available_metrics Sanbase.MCP.DataCatalog.AvailableMetrics.list()

  @spec get_all_projects() :: list(map())
  def get_all_projects() do
    cache_key = {__MODULE__, :get_all_projects} |> Sanbase.Cache.hash()

    {:ok, projects_data} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        san = Sanbase.Project.by_slug("santiment")

        projects = List.wrap(san) ++ Sanbase.Project.List.projects_page(1, 500)

        projects_data =
          Enum.map(projects, fn p ->
            %{
              name: p.name,
              slug: p.slug,
              ticker: p.ticker,
              description: p.description
            }
          end)

        {:ok, projects_data}
      end)

    projects_data
  end

  def available_slugs() do
    cache_key = {__MODULE__, :available_slugs} |> Sanbase.Cache.hash()

    {:ok, slugs} =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        projects = get_all_projects()
        slugs = Enum.map(projects, & &1.slug)
        {:ok, slugs}
      end)

    slugs
  end

  def available_metrics() do
    @available_metrics
    |> Enum.map(fn m ->
      {:ok, metadata} = Sanbase.Metric.metadata(m.name)
      # metatata.docs is a list of structs and structs cannot be serialized to JSON
      docs = metadata.docs |> Enum.map(fn d -> %{url: d.link} end)

      m
      |> Map.put(:documentation_urls, docs)
      |> Map.put(:min_interval, metadata.min_interval)
      |> Map.put(:default_aggregation, metadata.default_aggregation)
    end)
  end

  @doc "Get all available metrics"
  @spec get_all_metrics() :: list(map())
  def get_all_metrics, do: available_metrics()

  @doc "Get all available slugs"
  @spec get_all_slugs() :: list(String.t())
  def get_all_slugs, do: available_slugs()

  @doc "Get metric names only"
  @spec get_metric_names() :: list(String.t())
  def get_metric_names, do: available_metrics() |> Enum.map(& &1.name)

  @doc "Get available metrics for a specific slug"
  def get_available_metrics_for_slug(slug) do
    if valid_slug?(slug) do
      metrics_intersection = fn all_metrics_for_slug ->
        all_metrics_for_slug_mapset =
          MapSet.new(all_metrics_for_slug)

        Enum.reduce(available_metrics(), [], fn %{name: name} = metric, acc ->
          if MapSet.member?(all_metrics_for_slug_mapset, name) do
            [metric | acc]
          else
            acc
          end
        end)
      end

      case Sanbase.Metric.available_metrics_for_selector(%{slug: slug}) do
        {:ok, metrics} -> {:ok, metrics_intersection.(metrics)}
        {:nocache, {:ok, metrics}} -> {:ok, metrics_intersection.(metrics)}
      end
    else
      {:error, "Slug '#{slug}' not supported or mistyped."}
    end
  end

  @doc "Get available slugs for a specific metric"
  def get_available_slugs_for_metric(metric) do
    if metric in get_metric_names() do
      Sanbase.Metric.available_slugs(metric)
    else
      {:error, metric_not_found_error(metric)}
    end
  end

  def get_available_projects_for_metric(metric) do
    with projects when is_list(projects) <- get_all_projects(),
         {:ok, slugs} <- get_available_slugs_for_metric(metric) do
      slugs_mapset = MapSet.new(slugs)
      {:ok, Enum.filter(projects, fn p -> p.slug in slugs_mapset end)}
    end
  end

  @doc "Validate if a metric exists"
  def valid_metric?(metric), do: metric in get_metric_names()

  @doc """
  Suggest the closest metric name using Jaro distance.

  Returns `{:ok, name}` when a metric with Jaro distance >= 0.85 is found,
  or `:none` otherwise.

  ## Examples

      iex> Sanbase.MCP.DataCatalog.suggest_metric("price_uds")
      {:ok, "price_usd"}

      iex> Sanbase.MCP.DataCatalog.suggest_metric("zzz_nonexistent")
      :none
  """
  @spec suggest_metric(String.t()) :: {:ok, String.t()} | :none
  def suggest_metric(metric) do
    {best_name, best_distance} =
      get_metric_names()
      |> Enum.map(fn name -> {name, String.jaro_distance(metric, name)} end)
      |> Enum.max_by(fn {_name, distance} -> distance end)

    if best_distance >= 0.85, do: {:ok, best_name}, else: :none
  end

  @doc """
  Build an error message for an unsupported metric, with a fuzzy suggestion if available.

  ## Examples

      iex> Sanbase.MCP.DataCatalog.metric_not_found_error("price_uds")
      "Metric 'price_uds' is not supported. Did you mean 'price_usd'? Use the metrics_and_assets_discovery_tool to see all available metrics."

      iex> Sanbase.MCP.DataCatalog.metric_not_found_error("zzz_nonexistent")
      "Metric 'zzz_nonexistent' is not supported. Use the metrics_and_assets_discovery_tool to see all available metrics."
  """
  @spec metric_not_found_error(String.t()) :: String.t()
  def metric_not_found_error(metric) do
    base = "Metric '#{metric}' is not supported."

    suggestion =
      case suggest_metric(metric) do
        {:ok, name} -> " Did you mean '#{name}'?"
        :none -> ""
      end

    base <>
      suggestion <>
      " Use the metrics_and_assets_discovery_tool to see all available metrics."
  end

  @doc "Validate if a slug exists"
  def valid_slug?(slug), do: slug in available_slugs()

  @doc "Validate metric and slug combination"
  def validate_metric_slug_combination(metric, slug) do
    cond do
      not valid_slug?(slug) ->
        {:error, "Slug '#{slug}' mistyped or not supported."}

      not valid_metric?(metric) ->
        {:error, metric_not_found_error(metric)}

      true ->
        metric_info = Enum.find(available_metrics(), &(&1.name == metric))
        {:ok, metric_info}
    end
  end
end
