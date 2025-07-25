defmodule SanbaseWeb.MCP.FetchMetricDataTool do
  @moduledoc "Fetch metric data for the last 30 days with daily resolution"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response

  @valid_metrics ["price_usd", "social_volume_total", "github_activity"]

  schema do
    field(:metric, :string, required: true)
    field(:slug, :string, required: true)
  end

  @impl true
  def execute(%{metric: metric, slug: slug}, frame) do
    with {:ok, metric} <- validate_metric(metric),
         {:ok, data} <- fetch_metric_data(metric, slug) do
      response_data = %{
        metric: metric,
        slug: slug,
        data: data,
        period: "last_30_days",
        interval: "1d",
        data_points: length(data)
      }

      {:reply, Response.json(Response.tool(), response_data), frame}
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp validate_metric(metric) when metric in @valid_metrics, do: {:ok, metric}

  defp validate_metric(metric),
    do:
      {:error, "Invalid metric: #{metric}. Available metrics: #{Enum.join(@valid_metrics, ", ")}"}

  defp fetch_metric_data(metric, slug) do
    to = DateTime.utc_now()
    from = DateTime.add(to, -30, :day)
    interval = "1d"

    selector = %{slug: slug}

    case Sanbase.Metric.timeseries_data(metric, selector, from, to, interval) do
      {:ok, data} ->
        formatted_data =
          data
          |> Enum.map(fn %{datetime: datetime, value: value} ->
            %{
              datetime: DateTime.to_iso8601(datetime),
              value: value
            }
          end)

        {:ok, formatted_data}

      {:error, reason} ->
        {:error, "Failed to fetch data: #{inspect(reason)}"}

      _ ->
        {:error, "Unexpected response from metric API"}
    end
  end
end
