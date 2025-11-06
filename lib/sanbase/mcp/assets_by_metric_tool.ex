defmodule Sanbase.MCP.AssetsByMetricTool do
  @moduledoc """
  A powerful metrics-based project filtering and sorting tool that works with cryptocurrency assets
  based on their metrics and allows for ordered, paginated results.

  The tool allows for filtering assets by a metric and sorting them according to that same metric
  in ascending or descending metric, or just to sort the assets by a metric without filtering.

  This tool allows you to discover projects that meet specific criteria by analyzing their
  metrics over time periods. You can filter projects by absolute values (greater_than/less_than thresholds)
  or by percentage changes, or just sort projects by some metric.

  ## Use Cases
  - Get top 10 assets by marketcap, sorted in descending order
  - Get top 50 assets with highest dev_activity_1d
  - Find assets with price more than $10
  - Discover tokens whose price increased by more than 50% in the last 30 days
  - Screen for projects with market cap less than $100M
  - Identify assets that have dev_activity_1d decline by more than 20% in the past month

  ## Examples
  - Get projects that have a price_usd in the last 24 hours and it's greater_than $500. Get the first 20
    ordered by price_usd in descending order
    `{metric: "price_usd", operator: :greater_than, threshold: 500.0, from: "utc_now-24h", to: "utc_now", sort: "desc, page: 1, page_size: 20}`
  - Find projects whose price_usd today is 25% higher than 7 days ago, sorted by the highest percent increase in descending order. Get the first 100.
    `{metric: "price_usd", operator: :percent_up, threshold: 25.0, from: "utc_now-7d", to: "utc_now", sort: "desc", page: 1, page_size: 100}`
  - Projects with current market cap less_than $50M. Get 100 such projects, ordered by marketcap in descending order.
    `{metric: "marketcap_usd", operator: :less_than, threshold: 50000000.0, from: "utc_now-1d", to: "utc_now", sort: "desc", page: 1, page_size: 100}`

  Here is how the filtering works:
  - For absolute value operators - `greater_than` and `less_than` - fetch the `metric` for each asset in the interval
   `from`-`to`, aggregting it using the specified `aggregation` method (defaulting to the metric's default).
  - For percent change operators - `percent_up` and `percent_down` - fetch the `metric` for each asset
    in the interval `from-`to`, as well as in the same length interval immediately before `from`.
    The two resulting values are compared to calculate the percentage change.

  Some metrics like price_usd and marketcap_usd are aggregated with `LAST` aggregation by default,
  meaning that the last known value in the queried interval is used. For percent change, this means that
  the tool compares the last known price immediately before `from` and the last known price before `to`.
  Other metrics like transaction_volume_usd and social_volume_total (and most other volume metrics) are aggregated by
  default with SUM aggregation, meaning that the total combined sum in the queried interval is used. For these
  metrics length of the time window is vital. A common mistake is to try to check if the social_total_total for
  the last 5 minutes is greater_than some threshold. Five minutes is not enough for social volume to accumulate enough.
  In such scenarios use a longer time window like 1 day or more.
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response

  schema do
    field(:metric, :string,
      required: true,
      description: """
      The metric to use for screening projects. This determines what aspect of each project will be analyzed.
      Common metrics include: 'price_usd', 'marketcap_usd', 'volume_usd', 'dev_activity', 'social_volume', 'active_addresses'.
      Use the data catalog to discover all available metrics for comprehensive screening options.
      Discover the supported metrics with the metrics_and_assets_discovery_tool.
      """
    )

    field(:from, :string,
      required: true,
      description: """
      Start date/time for the analysis period. Defines the beginning of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-01-01T00:00:00Z") or relative time expressions
      (e.g., "utc_now-30d" for 30 days ago, "utc_now-1h" for 1 hour ago)
      Defaults to 30 days ago if not specified. Used with percentage operators to calculate change over time.
      """
    )

    field(:to, :string,
      required: true,
      description: """
      End date/time for the analysis period. Defines the end of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-12-31T23:59:59Z") or relative time expressions
      (e.g., "utc_now" for current time, "utc_now-1d" for yesterday). Defaults to current time if not specified.
      Must be after the 'from' date. Used with percentage operators to calculate change over the specified period.
      """
    )

    field(:operator, :enum,
      type: :string,
      values: ~w(greater_than less_than percent_up percent_down),
      required: false,
      description: """
      Comparison operator that determines how projects are filtered based on the metric and threshold.

      Absolute value operators (compare current values):
      - `greater_than` - Include projects where the aggregated metric value is greater than the threshold
      - `less_than` - Include projects where the aggregated metric value is less than the threshold

      Percentage change operators (compare change from 'from' to 'to' period):
      - `percent_up` - Include projects where the metric increased by more than the threshold percentage
      - `percent_down` - Include projects where the metric decreased by more than the threshold percentage


      If this parameter is not provided, the threshold parameter also must not be provided. If they are
      not provided, the tool will simply sort the assets and will do no filtering.

      Example: operator=percent_up, threshold=25.0 finds projects that gained more than 25%.
      """
    )

    field(:threshold, {:either, {:integer, :float}},
      required: false,
      description: """
      The numeric threshold value used for filtering projects. The meaning depends on the operator:

      For absolute operators (:greater_than, :less_than):
      - The actual metric value to compare against (e.g., 10.5 for price_usd greater_than $10.50)
      - Units match the metric (USD for price/market cap, count for addresses, etc.)

      For percentage operators (:percent_up, :percent_down):
      - The percentage change threshold (e.g., 25.0 for 25% change)
      - Always expressed as a positive number regardless of direction

      If this parameter is not provided, the operator parameter also must not be provided. If they are
      not provided, the tool will simply sort the assets and will do no filtering.

      Examples: threshold=50000000.0 with :less_than finds projects with market cap under $50M
      """
    )

    field(:aggregation, :enum,
      type: :string,
      values: ~w(min max sum first last avg),
      required: false,
      description: """
      Method for aggregating metric data over the specified time period. Determines how multiple data points
      within the time window are combined into a single value for comparison.

      Common aggregation methods:
      - "avg" - Average value over the period (default for most metrics)
      - "sum" - Total sum of values (useful for volume, transaction counts)
      - "max" - Maximum value in the period (highest price, peak activity)
      - "min" - Minimum value in the period (lowest price, minimum activity)
      - "last" - Most recent value in the period
      - "first" - Earliest value in the period

      If not specified, uses the metric's default aggregation, whichi is carefully selected based on the metric type.
      Some aggregations do not make sense for certain metrics (e.g., summing prices).
      If not specifically required, using the metric's default aggregation method is recommended.
      """
    )

    field(:page, :integer,
      required: true,
      description: """
      Page number for paginated results. Used to retrieve specific pages when the result set is large.
      Starts from 1 (first page). Combine with page_size to control how many results are returned per page.
      Useful when only the top 10, 20, 100, etc. assets are needed.
      """
    )

    field(:page_size, :integer,
      required: true,
      description: """
      Number of projects to return per page. Controls the size of each paginated response.
      Typical values range from 10-100 depending on your needs.
      """
    )

    field(:sort, :enum,
      type: :string,
      values: ~w(asc desc),
      required: true,
      description: """
      Sort order for the filtered results based on the aggregated metric values.
      - "asc" - Ascending order (lowest values first, e.g., cheapest prices first)
      - "desc" - Descending order (highest values first, e.g., most expensive prices first)

      Particularly useful when combined with pagination to get the top/bottom performers.
      Example: sort="desc" with price_usd shows highest-priced projects first.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    with :ok <- validate_operator_threshold_pair(params[:operator], params[:threshold]),
         :ok <- validate_aggregation(params[:aggregation]),
         :ok <- validate_sort(params[:sort]) do
      do_execute(params, frame)
    else
      {:error, reason} ->
        {:reply, Response.error(Response.tool(), reason), frame}
    end
  end

  defp do_execute(
         %{metric: metric, from: from, to: to, page: page, page_size: page_size} = params,
         frame
       ) do
    with {:ok, metadata} <- Sanbase.Metric.metadata(metric) do
      aggregation = Map.get(params, :aggregation)

      aggregation =
        if is_binary(aggregation),
          # credo:disable-for-next-line
          do: String.to_atom(aggregation),
          else: metadata.default_aggregation

      # credo:disable-for-next-line
      operator = if operator = params[:operator], do: String.to_atom(operator)
      threshold = params[:threshold]

      # If there's no operator and threshold
      filters =
        if not is_nil(operator) and not is_nil(threshold) do
          [
            %{
              name: "metric",
              args: %{
                metric: metric,
                from: from,
                to: to,
                aggregation: aggregation,
                operator: operator,
                threshold: threshold
              }
            }
          ]
        else
          []
        end

      pagination = %{page: page, page_size: page_size}

      order_by = %{metric: metric, from: from, to: to, direction: Map.get(params, :sort, "asc")}

      args = %{
        selector: %{
          filters: filters,
          pagination: pagination,
          order_by: order_by
        }
      }

      case Sanbase.Project.ListSelector.projects(args) do
        {:ok, %{projects: projects, total_projects_count: total_projects_count}} ->
          result = %{
            assets: Enum.map(projects, & &1.slug),
            page: page,
            page_size: page_size,
            total_assets: total_projects_count
          }

          {:reply, Response.json(Response.tool(), result), frame}
      end
    end
  end

  defp validate_aggregation(nil), do: :ok

  defp validate_aggregation(aggregation) when aggregation in ~w(min max sum first last avg),
    do: :ok

  defp validate_aggregation(aggregation),
    do:
      {:error,
       "Invalid aggregation '#{aggregation}'. Must be one of: min, max, sum, first, last, avg"}

  defp validate_sort(sort) when sort in ~w(asc desc), do: :ok
  defp validate_sort(nil), do: {:error, "Sort is required"}
  defp validate_sort(sort), do: {:error, "Invalid sort '#{sort}'. Must be one of: asc, desc"}

  defp validate_operator_threshold_pair(nil, nil), do: :ok

  defp validate_operator_threshold_pair(operator, threshold) do
    case {operator, threshold} do
      {nil, nil} ->
        :ok

      {bin, nil} when is_binary(bin) ->
        {:error,
         "Cannot provide `operator` threshold without also providing the `threshold` param"}

      {nil, num} when is_number(num) ->
        {:error,
         "Cannot provide `threshold` threshold without also providing the `operator` param"}

      _ ->
        :ok
    end
  end
end
