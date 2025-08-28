defmodule Sanbase.MCP.MetricsAndAssetsDiscoveryTool do
  @moduledoc """
  ## Metrics and Assets Discovery Tool

  This tool enables AI clients to intelligently explore and filter the available
  metrics and crypto assets (slugs) on the Sanbase platform.

  ### Capabilities

  - **List all metrics and assets:** Retrieve a comprehensive list of all supported
      metrics and crypto asset slugs.
  - **Filter by asset (slug):** Get all metrics available for a specific asset
      by providing its slug (e.g., `"bitcoin"`, `"ethereum"`).
  - **Filter by metric:** Discover which assets support a specific metric by
      providing the metric name (e.g., `"price_usd"`, `"marketcap_usd"`).
  - **Combined filtering:** Find if a particular metric is available for a specific
      asset by providing both the slug and metric.

  ### Usage Guidance

  - **slug**: The unique, lowercase, hyphen-separated identifier for a crypto asset
    (e.g., "bitcoin"). Use this to focus results on a single asset.
  - **metric**: The unique, lowercase, snake_case identifier for a metric
    (e.g., "price_usd"). Use this to focus results on a single metric.
  - **interval**: The datetime interval between two data points in the result.
    (e.g. 5m means 5 minutes, 1h means 1 hour, 2d means 2 days, etc.). Default is 1d.
  - **time_period**: How far back in time to fetch data. Examples: "7d" (7 days),
    "30d" (30 days), etc. Default is 30d.

  ### Example Parameters

  - **List all metrics and assets:**
    ```
    {}
    ```
  - **List all metrics for Ethereum:**
    ```
    { "slug": "ethereum" }
    ```
  - **List all assets supporting the `price_usd` metric:**
    ```
    { "metric": "price_usd" }
    ```
  - **Check if `daily_active_addresses` is available for Bitcoin:**
    ```
    { "slug": "bitcoin", "metric": "daily_active_addresses" }
    ```
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.DataCatalog

  schema do
    field(:slug, :string,
      required: false,
      description: """
      The unique identifier (slug) for a specific crypto asset such as 'bitcoin' or 'ethereum'.
      Use this field to filter results to a single asset. Slugs are lowercase,
      hyphen-separated names used throughout the platform.
      """
    )

    field(:metric, :string,
      required: false,
      description: """
      The unique identifier for a specific metric, such as 'price_usd',
      'marketcap_usd', or 'daily_active_addresses'. Metrics are lowercase and snake_case.
      Use this field to filter results to a single metric across all assets
      or in combination with a specific slug. Metrics represent quantitative or
      qualitative data points tracked for crypto assets and are used throughout
      the platform for analysis and insights.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    do_execute(params, frame)
  end

  defp do_execute(params, frame) do
    response_data =
      case {params[:slug], params[:metric]} do
        {nil, nil} -> get_data(nil, nil)
        {slug, nil} when is_binary(slug) -> get_data(slug, _metric = nil)
        {nil, metric} when is_binary(metric) -> get_data(_slug = nil, metric)
        {slug, metric} when is_binary(slug) and is_binary(metric) -> get_data(slug, metric)
      end

    {:reply, Response.json(Response.tool(), response_data), frame}
  end

  defp get_data(nil = _slug, nil = _metric) do
    assets = DataCatalog.get_all_projects()
    metrics = DataCatalog.get_all_metrics()
    # Return everything
    %{
      metrics: metrics,
      assets: assets,
      metrics_count: length(metrics),
      assets_count: length(assets),
      description: "All available metrics and slugs"
    }
  end

  defp get_data(slug, nil = _metric) do
    # Return metrics for specific slug
    case DataCatalog.get_available_metrics_for_slug(slug) do
      {:ok, metrics} ->
        %{
          slug: slug,
          metrics: metrics,
          metrics_count: length(metrics),
          description: "All metrics available for #{slug}"
        }

      {:error, reason} ->
        %{
          error: reason,
          available_assets: DataCatalog.get_all_projects()
        }
    end
  end

  defp get_data(nil = _slug, metric) do
    # Return slugs for specific metric
    case DataCatalog.get_available_projects_for_metric(metric) do
      {:ok, assets} ->
        %{
          metric: metric,
          assets: assets,
          assets_count: length(assets),
          description: "All slugs available for #{metric} metric"
        }

      {:error, reason} ->
        %{
          error: reason,
          available_metrics: DataCatalog.get_metric_names()
        }
    end
  end

  defp get_data(slug, metric) do
    # Validate specific combination
    case DataCatalog.validate_metric_slug_combination(metric, slug) do
      {:ok, metric_info} ->
        %{
          slug: slug,
          metric: metric_info,
          available: true,
          description: "#{metric} is available for #{slug}"
        }

      {:error, reason} ->
        %{error: reason}
    end
  end
end
