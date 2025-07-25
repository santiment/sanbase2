defmodule SanbaseWeb.MCP.AvailableMetricsTool do
  @moduledoc "List available metrics for MCP clients"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  @predefined_metrics [
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
    }
  ]

  schema do
  end

  @impl true
  def execute(_params, frame) do
    response_data = %{
      metrics: @predefined_metrics,
      total_count: length(@predefined_metrics),
      description: "Available metrics for data fetching"
    }

    {:reply, Response.json(Response.tool(), response_data), frame}
  end
end
