defmodule Sanbase.MCP.MetricsAndAssetsDiscoveryTool do
  @moduledoc """
  Catalog lookup: which metrics and which crypto assets (slugs) Santiment
  supports, and whether a given metric exists for a given asset. Returns names
  and metadata only — it never returns metric values or timeseries.

  ## When to use

  - Resolve a name before any data call: turn "Ethereum" into the slug
    `ethereum`, or "active addresses" into the metric `daily_active_addresses`.
  - Check availability before calling `fetch_metric_data_tool`,
    `assets_by_metric_tool` or `show_chart`, so a bad slug/metric does not
    waste a data call.
  - Recover from a "metric/slug not supported" error from any other tool.

  ## When not to use

  - Actual metric values over time — use `fetch_metric_data_tool`.
  - Ranking, filtering or screening assets by a metric value — use
    `assets_by_metric_tool`.
  - Rendering a chart — use `show_chart`.
  - Trending words/stories or insights — use `combined_trends_tool` or
    `insight_discovery_tool`. Those data sets are not in this catalog.

  ## Parameters

  Both parameters are optional and the four combinations do four different
  things:

  | Arguments                  | Returns                                           |
  |----------------------------|---------------------------------------------------|
  | `{}`                       | Every supported metric and every supported asset  |
  | `{"slug": ...}`            | All metrics available for that one asset          |
  | `{"metric": ...}`          | All assets that support that one metric           |
  | `{"slug":..., "metric":...}`| Whether that exact pair is available (validation) |

  - `slug` — lowercase, hyphen-separated asset id: `"bitcoin"`, `"ethereum"`,
    `"avalanche"`. Not a ticker: use `"bitcoin"`, not `"BTC"`. One slug per
    call; lists are not accepted.
  - `metric` — lowercase snake_case metric id: `"price_usd"`,
    `"marketcap_usd"`, `"daily_active_addresses"`. One metric per call.

  Examples:

      {}
      {"slug": "ethereum"}
      {"metric": "price_usd"}
      {"slug": "bitcoin", "metric": "daily_active_addresses"}

  ## Behavior

  - Read-only: no writes, no state change, nothing destructive.
  - Requires an authenticated Santiment account (API key or OAuth token);
    every call counts against the account plan's MCP rate limits.
  - Results are cached server-side, so the catalog can lag a newly listed asset
    by a few minutes.
  - Large responses (notably `{}`, which covers ~500 assets) are truncated to
    stay under the client token limit. When that happens the response carries
    `"truncated": true` plus `"truncation_notice"`, and the counts are adjusted
    to what was actually returned — pass `slug` or `metric` to get a complete
    answer instead of a truncated one.

  ## Response

  Always a JSON object. Its shape depends on the arguments.

  `{}` — full catalog:

      {
        "metrics": [{"name": "price_usd", "description": "...", "unit": "USD",
                     "supports_many_slugs": true, "min_interval": "1m",
                     "default_aggregation": "last",
                     "documentation_urls": [{"url": "..."}]}],
        "assets": [{"name": "Bitcoin", "slug": "bitcoin", "ticker": "BTC"}],
        "metrics_count": 120, "assets_count": 500, "description": "..."
      }

  `{"slug": ...}` — `{"slug", "metrics" (same metric objects as above),
  "metrics_count", "description"}`.

  `{"metric": ...}` — `{"metric", "assets" (same asset objects as above),
  "assets_count", "description"}`.

  `{"slug": ..., "metric": ...}` — on success
  `{"slug", "metric": <metric object>, "available": true, "description"}`.

  Unsupported input is reported inside a successful response, not as a tool
  error: an unknown `slug` yields `{"error": "...", "available_assets": [...]}`,
  an unknown `metric` yields `{"error": "...", "available_metrics": [...]}`.
  There is no `"available": false` — read `error`. Error messages include a
  fuzzy suggestion for near-miss metric names (`price_uds` -> `price_usd`), so
  retry with the suggested name.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.{DataCatalog, Utils}

  @impl true
  def annotations do
    %{
      "title" => "Metrics and Assets Discovery",
      "readOnlyHint" => true,
      "destructiveHint" => false,
      "openWorldHint" => false
    }
  end

  schema do
    field(:slug, :string,
      required: false,
      description: """
      Santiment slug of one crypto asset: lowercase, hyphen-separated, e.g.
      'bitcoin', 'ethereum', 'avalanche'. Not a ticker - use 'bitcoin', not
      'BTC'. One slug per call; lists are not accepted.

      Alone: returns all metrics available for this asset. With `metric`:
      checks only whether that metric exists for this asset. Omit both to list
      the whole catalog.
      """
    )

    field(:metric, :string,
      required: false,
      description: """
      Santiment id of one metric: lowercase snake_case, e.g. 'price_usd',
      'marketcap_usd', 'daily_active_addresses'. One metric per call; lists are
      not accepted.

      Alone: returns all assets that support this metric. With `slug`: checks
      only whether this metric exists for that asset. Omit both to list the
      whole catalog.
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

    {:reply, Response.json(Response.tool(), Utils.truncate_response(response_data)), frame}
  end

  defp get_data(nil = _slug, nil = _metric) do
    assets = DataCatalog.get_all_projects() |> compact_projects()
    metrics = DataCatalog.get_all_metrics()
    # Return everything
    %{
      metrics: metrics,
      assets: assets,
      metrics_count: length(metrics),
      assets_count: length(assets),
      description: "All available metrics and slugs. Use slug filter for full asset details."
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
          assets: compact_projects(assets),
          assets_count: length(assets),
          description:
            "All slugs available for #{metric} metric. Use slug filter for full asset details."
        }

      {:error, error} ->
        %{
          error: error,
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

  defp compact_projects(projects) do
    Enum.map(projects, &Map.delete(&1, :description))
  end
end
