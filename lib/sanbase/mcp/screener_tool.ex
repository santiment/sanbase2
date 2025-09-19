defmodule Sanbase.MCP.FilterAssetsByMetricTool do
  @moduledoc """
  A powerful metrics-based project screening tool that filters cryptocurrency projects based on their performance metrics.

  This tool allows you to discover projects that meet specific criteria by analyzing their metrics over time periods.
  You can filter projects by absolute values (above/below thresholds) or by percentage changes (growth/decline).

  ## Use Cases
  - Find projects with price above $10
  - Discover tokens that increased by more than 50% in the last 30 days
  - Screen for projects with market cap below $100M
  - Identify assets that declined by more than 20% recently
  - Filter by any supported metric with custom time periods and aggregation methods

  ## Examples
  - Screen for projects with price_usd above $5: `{metric: "price_usd", operator: :above, threshold: 5.0}`
  - Find projects up 25% in last week: `{metric: "price_usd", operator: :percent_up, threshold: 25.0, from: "utc_now-7d"}`
  - Projects with market cap below $50M: `{metric: "marketcap_usd", operator: :below, threshold: 50000000.0}`
  """

  use Anubis.Server.Component, type: :tool

  alias Anubis.Server.Response
  alias Sanbase.MCP.DataCatalog

  @slugs_per_call_limit 10
  schema do
    field(:metric, :string,
      required: true,
      description: """
      The metric to use for screening projects. This determines what aspect of each project will be analyzed.
      Common metrics include: 'price_usd', 'marketcap_usd', 'volume_usd', 'dev_activity', 'social_volume', 'active_addresses'.
      Use the data catalog to discover all available metrics for comprehensive screening options.
      """
    )

    field(:from, :string,
      required: false,
      description: """
      Start date/time for the analysis period. Defines the beginning of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-01-01T00:00:00Z") or relative time expressions
      (e.g., "utc_now-30d" for 30 days ago, "utc_now-1h" for 1 hour ago)
      Defaults to 30 days ago if not specified. Used with percentage operators to calculate change over time.
      """
    )

    field(:to, :string,
      required: false,
      description: """
      End date/time for the analysis period. Defines the end of the time window for metric aggregation.
      Accepts ISO 8601 datetime strings (e.g., "2024-12-31T23:59:59Z") or relative time expressions
      (e.g., "utc_now" for current time, "utc_now-1d" for yesterday). Defaults to current time if not specified.
      Must be after the 'from' date. Used with percentage operators to calculate change over the specified period.
      """
    )

    field(:operator, {:enum, [:above, :below, :percent_up, :percent_down]},
      required: true,
      description: """
      Comparison operator that determines how projects are filtered based on the metric and threshold.

      Absolute value operators (compare current values):
      - `above` - Include projects where the aggregated metric value is greater than the threshold
      - `below` - Include projects where the aggregated metric value is less than the threshold

      Percentage change operators (compare change from 'from' to 'to' period):
      - `percent_up` - Include projects where the metric increased by more than the threshold percentage
      - `percent_down` - Include projects where the metric decreased by more than the threshold percentage

      Example: operator=percent_up, threshold=25.0 finds projects that gained more than 25%
      """
    )

    field(:threshold, :float,
      required: true,
      description: """
      The numeric threshold value used for filtering projects. The meaning depends on the operator:

      For absolute operators (:above, :below):
      - The actual metric value to compare against (e.g., 10.5 for price_usd above $10.50)
      - Units match the metric (USD for price/market cap, count for addresses, etc.)

      For percentage operators (:percent_up, :percent_down):
      - The percentage change threshold (e.g., 25.0 for 25% change)
      - Always expressed as a positive number regardless of direction

      Examples: threshold=50000000.0 with :below finds projects with market cap under $50M
      """
    )

    field(:aggregation, {:enum, [:min, :max, :sum, :first, :last, :avg]},
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

      If not specified, uses the metric's default aggregation method.
      If not specifically required, using the metric's default aggregation method is recommended.
      """
    )

    field(:page, :integer,
      required: false,
      description: """
      Page number for paginated results. Used to retrieve specific pages when the result set is large.
      Starts from 1 (first page). Combine with page_size to control how many results are returned per page.
      Useful for processing large screening results in manageable chunks.
      """
    )

    field(:page_size, :integer,
      required: false,
      description: """
      Number of projects to return per page. Controls the size of each paginated response.
      Typical values range from 10-100 depending on your needs. Smaller page sizes provide faster responses
      and lower memory usage, while larger sizes reduce the number of API calls needed.
      Default page size is applied if not specified.
      """
    )

    field(:sort, {:enum, ["ASC", "DESC"]},
      required: false,
      description: """
      Sort order for the filtered results based on the aggregated metric values.
      - "ASC" - Ascending order (lowest values first, e.g., cheapest prices first)
      - "DESC" - Descending order (highest values first, e.g., most expensive prices first)

      Particularly useful when combined with pagination to get the top/bottom performers.
      Example: sort="DESC" with price_usd shows highest-priced projects first.
      """
    )
  end

  @impl true
  def execute(params, frame) do
    # Note: Do it like this so we can wrap it in an if can_execute?/3 clause
    # so the execute/2 function itself is not
    do_execute(params, frame)
  end

  defp do_execute(%{metric: metric, slugs: slugs} = params, frame) do
  end
end
