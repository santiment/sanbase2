/**
 * Baked-in example queries for the Santiment GraphiQL interface.
 *
 * Each entry has:
 *   - name: short title shown in the sidebar
 *   - description: one-line description shown below the title
 *   - query: the GraphQL query (use backtick template literals for multiline)
 *   - variables: (optional) JSON string of variables
 */
export default [
  // ─── Discovery: Assets ────────────────────────────────────────

  {
    name: "List All Projects",
    description: "Get all available projects with their slug, name, and ticker",
    query: `\
{
  allProjects {
    slug
    name
    ticker
  }
}`,
  },
  {
    name: "Get Project Details",
    description: "Look up a specific project by slug with links and metadata",
    query: `\
{
  projectBySlug(slug: "bitcoin") {
    slug
    name
    ticker
    description
    logoUrl
    websiteLink
    twitterLink
    discordLink
    telegramLink
    marketSegments
    githubLinks
    infrastructure
  }
}`,
  },

  // ─── Discovery: Metrics ───────────────────────────────────────

  {
    name: "List All Available Metrics",
    description: "Get the full list of metrics available in the API",
    query: `\
{
  getAvailableMetrics
}`,
  },
  {
    name: "Available Metrics for a Project",
    description: "Which metrics are available for a given project, by type",
    query: `\
{
  projectBySlug(slug: "bitcoin") {
    availableMetrics
    availableTimeseriesMetrics
    availableHistogramMetrics
    availableMetricsExtended {
      metric
      docs {
        link
      }
    }
  }
}`,
  },
  {
    name: "Metric Metadata",
    description: "Aggregations, selectors, data type, default aggregation, min interval",
    query: `\
{
  getMetric(metric: "daily_active_addresses") {
    metadata {
      availableAggregations
      availableSelectors
      availableSlugs
      dataType
      defaultAggregation
      minInterval
    }
  }
}`,
  },
  {
    name: "Projects Available for a Metric",
    description: "Find which assets have data for a specific metric",
    query: `\
{
  getMetric(metric: "daily_active_addresses") {
    metadata {
      availableProjects {
        slug
      }
    }
  }
}`,
  },
  {
    name: "Metric Available Since",
    description: "Check from which date a metric is available for an asset",
    query: `\
{
  getMetric(metric: "transaction_volume") {
    availableSince(slug: "bitcoin")
  }
}`,
  },
  {
    name: "Metric Last Computed At",
    description: "When was the latest data point computed for a metric/asset",
    query: `\
{
  getMetric(metric: "daily_active_addresses") {
    lastDatetimeComputedAt(slug: "santiment")
  }
}`,
  },

  // ─── Timeseries: Single Asset ─────────────────────────────────

  {
    name: "Daily Active Addresses",
    description: "Basic timeseries query — daily active addresses for Bitcoin",
    query: `\
{
  getMetric(metric: "daily_active_addresses") {
    timeseriesDataJson(
      selector: { slug: "bitcoin" }
      from: "utc_now-30d"
      to: "utc_now"
      interval: "1d"
    )
  }
}`,
  },
  {
    name: "Dev Activity (Relative Dates)",
    description: "Fetch dev activity using utc_now-Nd relative date syntax",
    query: `\
{
  getMetric(metric: "dev_activity") {
    timeseriesDataJson(
      slug: "ethereum"
      from: "utc_now-60d"
      to: "utc_now"
      interval: "1d"
    )
  }
}`,
  },

  // ─── Timeseries: Transformations ──────────────────────────────

  {
    name: "Dev Activity with Moving Average",
    description: "Apply a 4-period moving average to smooth the data",
    query: `\
{
  getMetric(metric: "dev_activity") {
    timeseriesDataJson(
      slug: "ethereum"
      from: "utc_now-365d"
      to: "utc_now"
      interval: "7d"
      transform: { type: "moving_average", movingAverageBase: 4 }
    )
  }
}`,
  },
  {
    name: "Twitter Followers Weekly Change",
    description: "Consecutive differences — see week-over-week change instead of total",
    query: `\
{
  getMetric(metric: "twitter_followers") {
    timeseriesDataJson(
      slug: "ethereum"
      from: "utc_now-365d"
      to: "utc_now"
      interval: "7d"
      transform: { type: "consecutive_differences" }
    )
  }
}`,
  },

  // ─── Timeseries: Multiple Assets ──────────────────────────────

  {
    name: "Price for Multiple Assets",
    description: "Fetch price data for several assets in a single request",
    query: `\
{
  getMetric(metric: "price_usd") {
    timeseriesDataPerSlugJson(
      selector: { slugs: ["bitcoin", "ethereum"] }
      from: "utc_now-30d"
      to: "utc_now"
      includeIncompleteData: true
      interval: "1d"
    )
  }
}`,
  },

  // ─── Aggregated Data ──────────────────────────────────────────

  {
    name: "Current Prices for All Assets",
    description: "Latest price for every project using LAST aggregation",
    query: `\
{
  allProjects {
    slug
    price: aggregatedTimeseriesData(
      metric: "price_usd"
      from: "utc_now-1d"
      to: "utc_now"
      aggregation: LAST
    )
  }
}`,
  },
  {
    name: "Multiple Metrics per Asset",
    description: "Latest price, weekly high, and 30d dev activity using aliases",
    query: `\
{
  allProjects(page: 1, pageSize: 50) {
    slug
    name
    ticker
    latestPrice: aggregatedTimeseriesData(
      metric: "price_usd"
      aggregation: LAST
      from: "utc_now-1d"
      to: "utc_now"
    )
    highestWeeklyPrice: aggregatedTimeseriesData(
      metric: "price_usd"
      aggregation: MAX
      from: "utc_now-7d"
      to: "utc_now"
    )
    devActivity30d: aggregatedTimeseriesData(
      metric: "dev_activity_1d"
      aggregation: SUM
      from: "utc_now-30d"
      to: "utc_now"
    )
  }
}`,
  },
  {
    name: "Highest and Lowest DAA",
    description: "MAX and MIN daily active addresses using aliases in one query",
    query: `\
{
  getMetric(metric: "daily_active_addresses") {
    highest_daa: aggregatedTimeseriesData(
      slug: "ethereum"
      from: "2024-01-01T00:00:00Z"
      to: "2025-01-01T00:00:00Z"
      aggregation: MAX
    )
    lowest_daa: aggregatedTimeseriesData(
      slug: "ethereum"
      from: "2024-01-01T00:00:00Z"
      to: "2025-01-01T00:00:00Z"
      aggregation: MIN
    )
  }
}`,
  },

  // ─── Filtering and Ordering ───────────────────────────────────

  {
    name: "Filter and Order Assets",
    description: "Filter by min DAA, order by DAA descending, paginate results",
    query: `\
{
  allProjects(
    selector: {
      baseProjects: [
        { watchlistSlug: "stablecoins" }
        { slugs: ["santiment", "bitcoin", "ethereum"] }
      ]
      filters: [
        {
          metric: "daily_active_addresses"
          from: "utc_now-7d"
          to: "utc_now"
          aggregation: AVG
          operator: GREATER_THAN
          threshold: 1000
        }
      ]
      orderBy: {
        metric: "daily_active_addresses"
        from: "utc_now-3d"
        to: "utc_now"
        aggregation: LAST
        direction: DESC
      }
      pagination: { page: 1, pageSize: 10 }
    }
  ) {
    slug
    avgDaa7d: aggregatedTimeseriesData(
      metric: "daily_active_addresses"
      from: "utc_now-7d"
      to: "utc_now"
      aggregation: AVG
    )
  }
}`,
  },

  // ─── Histogram Data ───────────────────────────────────────────

  {
    name: "Age Distribution Histogram",
    description: "Token age distribution for Ethereum — how tokens are distributed by age",
    query: `\
{
  getMetric(metric: "age_distribution") {
    histogramData(
      slug: "ethereum"
      from: "utc_now-90d"
      to: "utc_now-80d"
      limit: 20
    ) {
      labels
      values {
        ... on FloatList {
          data
        }
      }
    }
  }
}`,
  },

  // ─── Social / Trending ────────────────────────────────────────

  {
    name: "Current Trending Words",
    description: "Top trending words in crypto social media over the last 3 hours",
    query: `\
{
  getTrendingWords(
    from: "utc_now-3h"
    to: "utc_now"
    size: 20
    interval: "1h"
  ) {
    datetime
    topWords {
      word
      score
    }
  }
}`,
  },

  // ─── Historical Balances ──────────────────────────────────────

  {
    name: "Historical Balance for an Address",
    description: "Token balance over time for a specific blockchain address",
    query: `\
query historicalBalance(
  $from: DateTime!
  $to: DateTime!
  $address: String!
  $interval: interval!
  $slug: String!
  $infrastructure: String
) {
  historicalBalance(
    address: $address
    interval: $interval
    from: $from
    to: $to
    selector: { slug: $slug, infrastructure: $infrastructure }
  ) {
    datetime
    balance
  }
}`,
    variables: `\
{
  "address": "0xbc4ca0eda7647a8ab7c2061c2e118a18a936f13d",
  "from": "2024-01-01T00:00:00.000Z",
  "interval": "1d",
  "slug": "weth",
  "to": "2024-04-01T00:00:00.000Z"
}`,
  },
  {
    name: "Labelled Historical Balance",
    description: "Total ETH balance of all centralized exchange addresses",
    query: `\
{
  getMetric(metric: "labelled_historical_balance") {
    timeseriesDataJson(
      from: "utc_now-30d"
      to: "utc_now"
      interval: "1d"
      selector: {
        labelFqn: "santiment/centralized_exchange:v1"
        slug: "ethereum"
      }
    )
  }
}`,
  },

  // ─── Metric Versions ──────────────────────────────────────────

  {
    name: "Compare Metric Versions",
    description: "Fetch data from different metric versions side by side using aliases",
    query: `\
{
  v1: getMetric(metric: "social_volume_total", version: "1.0") {
    timeseriesDataJson(
      slug: "bitcoin"
      from: "utc_now-30d"
      to: "utc_now"
      interval: "1d"
    )
  }
  v2: getMetric(metric: "social_volume_total", version: "2.0") {
    timeseriesDataJson(
      slug: "bitcoin"
      from: "utc_now-30d"
      to: "utc_now"
      interval: "1d"
    )
  }
}`,
  },

  // ─── Access & Plan Info ───────────────────────────────────────

  {
    name: "Access Restrictions for Plan",
    description: "Metric access restrictions, time ranges, and deprecation status for a plan",
    query: `\
{
  getAccessRestrictions(filter: METRIC, product: SANAPI, plan: BUSINESS_PRO) {
    name
    isAccessible
    isRestricted
    isDeprecated
    restrictedFrom
    restrictedTo
    minInterval
  }
}`,
  },

  // ─── Raw SQL ──────────────────────────────────────────────────

  {
    name: "Run Raw SQL Query",
    description: "Execute custom SQL against ClickHouse (requires authentication)",
    query: `\
{
  runRawSqlQuery(
    sqlQueryText: """
      SELECT
        get_metric_name(metric_id) AS metric,
        get_asset_name(asset_id) AS asset,
        dt,
        argMax(value, computed_at) AS value
      FROM daily_metrics_v2
      WHERE
        asset_id = get_asset_id({{slug}}) AND
        metric_id = get_metric_id({{metric}}) AND
        dt >= now() - INTERVAL {{last_n_days}} DAY
      GROUP BY dt, metric_id, asset_id
      ORDER BY dt ASC
    """
    sqlQueryParameters: "{\\"slug\\": \\"bitcoin\\", \\"last_n_days\\": 7, \\"metric\\": \\"nvt\\"}"
  ) {
    columns
    columnTypes
    rows
  }
}`,
  },
];
