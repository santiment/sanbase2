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
      nil
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
      {:error, "Metric '#{metric}' not supported or mistyped."}
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

  @doc "Validate if a slug exists"
  def valid_slug?(slug), do: slug in available_slugs()

  @doc "Validate metric and slug combination"
  def validate_metric_slug_combination(metric, slug) do
    cond do
      not valid_slug?(slug) ->
        {:error, "Slug '#{slug}' mistyped or not supported."}

      not valid_metric?(metric) ->
        {:error, "Metric '#{metric}' mistyped or not supported."}

      true ->
        metric_info = Enum.find(available_metrics(), &(&1.name == metric))
        {:ok, metric_info}
    end
  end
end
