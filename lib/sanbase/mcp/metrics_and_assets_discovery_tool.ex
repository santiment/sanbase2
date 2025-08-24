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

  - **`slug`**: The unique, lowercase, hyphen-separated identifier for a crypto asset
    (e.g., `"bitcoin"`). Use this to focus results on a single asset.
  - **`metric`**: The unique, lowercase, snake_case identifier for a metric
    (e.g., `"price_usd"`). Use this to focus results on a single metric.

  ### Example Parameters

  - **Li st all metrics and assets:**
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

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
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
        {nil, nil} ->
          assets = DataCatalog.get_all_projects() |> dbg()
          metrics = DataCatalog.get_all_metrics() |> dbg()
          # Return everything
          %{
            metrics: metrics,
            assets: assets,
            metrics_count: length(metrics),
            assets_count: length(assets),
            description: "All available metrics and slugs"
          }

        {slug, nil} ->
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

        {nil, metric} ->
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

        {slug, metric} ->
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

    {:reply, Response.json(Response.tool(), response_data), frame}
  end
end
