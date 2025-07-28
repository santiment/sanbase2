defmodule Sanbase.MCP.DataCatalog do
  @moduledoc "Centralized catalog of available metrics and slugs for MCP tools"

  @available_slugs ["bitcoin", "ethereum", "santiment"]

  @available_metrics [
    %{
      name: "price_usd",
      description: "Price in USD for cryptocurrencies",
      unit: "USD"
    },
    %{
      name: "social_volume_total",
      description: "Total social media mentions and discussions",
      unit: "count"
    },
    %{
      name: "github_activity",
      description: "Development activity on GitHub repositories",
      unit: "count"
    },
    %{
      name: "daily_active_addresses",
      description: "Daily active addresses",
      unit: "count"
    }
  ]

  @doc "Get all available metrics"
  def get_all_metrics, do: @available_metrics

  @doc "Get all available slugs"
  def get_all_slugs, do: @available_slugs

  @doc "Get metric names only"
  def get_metric_names, do: Enum.map(@available_metrics, & &1.name)

  @doc "Get available metrics for a specific slug"
  def get_available_metrics_for_slug(slug) do
    if slug in @available_slugs do
      {:ok, @available_metrics}
    else
      {:error, "Slug '#{slug}' not found"}
    end
  end

  @doc "Get available slugs for a specific metric"
  def get_available_slugs_for_metric(metric) do
    if metric in get_metric_names() do
      {:ok, @available_slugs}
    else
      {:error, "Metric '#{metric}' not found"}
    end
  end

  @doc "Validate if a metric exists"
  def valid_metric?(metric), do: metric in get_metric_names()

  @doc "Validate if a slug exists"
  def valid_slug?(slug), do: slug in @available_slugs

  @doc "Validate metric and slug combination"
  def validate_metric_slug_combination(metric, slug) do
    cond do
      not valid_slug?(slug) ->
        {:error,
         "Slug '#{slug}' not found. Available slugs: #{Enum.join(@available_slugs, ", ")}"}

      not valid_metric?(metric) ->
        {:error,
         "Metric '#{metric}' not found. Available metrics: #{Enum.join(get_metric_names(), ", ")}"}

      true ->
        metric_info = Enum.find(@available_metrics, &(&1.name == metric))
        {:ok, metric_info}
    end
  end
end
