defmodule Sanbase.MCP.DiscoveryTool do
  @moduledoc "Smart discovery tool for metrics and slugs with optional filtering"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Sanbase.MCP.DataCatalog

  schema do
    field(:slug, :string,
      required: false,
      description: "Filter by specific slug (e.g., 'bitcoin')"
    )

    field(:metric, :string,
      required: false,
      description: "Filter by specific metric (e.g., 'price_usd')"
    )
  end

  @impl true
  def execute(params, frame) do
    response_data =
      case {params[:slug], params[:metric]} do
        {nil, nil} ->
          # Return everything
          %{
            metrics: DataCatalog.get_all_metrics(),
            slugs: DataCatalog.get_all_slugs(),
            total_metrics: length(DataCatalog.get_all_metrics()),
            total_slugs: length(DataCatalog.get_all_slugs()),
            description: "All available metrics and slugs"
          }

        {slug, nil} ->
          # Return metrics for specific slug
          case DataCatalog.get_available_metrics_for_slug(slug) do
            {:ok, metrics} ->
              %{
                slug: slug,
                metrics: metrics,
                total_metrics: length(metrics),
                description: "All metrics available for #{slug}"
              }

            {:error, reason} ->
              %{
                error: reason,
                available_slugs: DataCatalog.get_all_slugs()
              }
          end

        {nil, metric} ->
          # Return slugs for specific metric
          case DataCatalog.get_available_slugs_for_metric(metric) do
            {:ok, slugs} ->
              %{
                metric: metric,
                slugs: slugs,
                total_slugs: length(slugs),
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
