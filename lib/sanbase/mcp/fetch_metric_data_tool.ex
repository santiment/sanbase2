defmodule Sanbase.MCP.FetchMetricDataTool do
  @moduledoc "Fetch metric data for the last 30 days with daily resolution"

  use Hermes.Server.Component, type: :tool

  alias Hermes.Server.Response
  alias Sanbase.MCP.DataCatalog

  schema do
    field(:metric, :string,
      required: true,
      description: "Metric name to fetch (e.g., 'price_usd')"
    )

    field(:slug, :string, required: true, description: "Slug identifier (e.g., 'bitcoin')")
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    do_execute(params, frame)
  end

  defp do_execute(%{metric: metric, slug: slug}, frame) do
    with {:ok, _metric} <- validate_metric(metric),
         {:ok, _slug} <- validate_slug(slug),
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

  defp validate_metric(metric) do
    if DataCatalog.valid_metric?(metric) do
      {:ok, metric}
    else
      {:error, "Metric '#{metric}' mistyped or not supported."}
    end
  end

  defp validate_slug(slug) do
    if DataCatalog.valid_slug?(slug) do
      {:ok, slug}
    else
      {:error, "Slug '#{slug}' mistyped or not supported."}
    end
  end

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
        {:error, "Failed to fetch #{metric} for #{slug}. Reason: #{reason}"}

      _ ->
        {:error, "Unexpected response from metric API"}
    end
  end
end
