defmodule SanbaseWeb.AvailableMetricsDescription do
  import Phoenix.Component

  def get_popover_text(%{key: "Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the public API.
    For example, if the metric is `price_usd` it is provided as the `metric` argument.

    Example:

      {
        getMetric(<b>metric: "price_usd"</b>){
          timeseriesData(asset: "ethereum" from: "utc_now-90d" to: "utc_now" interval: "1d"){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Internal Name"} = assigns) do
    ~H"""
    <pre>
    The name of the metric that is used in the database tables.
    The database tables are accessed through Santiment Queries when the
    user interacts with the data via SQL.

    How to use Santiment Queries, check <.link href={"https://academy.santiment.net/santiment-queries"} class="underline text-blue-600">this link</.link>
    </pre>
    """
  end

  def get_popover_text(%{key: "Clickhouse Table"} = assigns) do
    ~H"""
    <pre>
    Specify the name of the clickhouse table in which the metric is stored
    </pre>
    """
  end

  def get_popover_text(%{key: "Frequency"} = assigns) do
    ~H"""
    <pre>
    The minimum interval at which the metric is updated.

    For more details check <.link href="https://academy.santiment.net/metrics/details/frequency" class="underline text-blue-600">this link</.link>
    </pre>
    """
  end

  def get_popover_text(%{key: "Min Plan"} = assigns) do
    ~H"""
    <pre>
    Controls what is the lowest subscription plan per product
    that this metric is accessible.
    </pre>
    """
  end

  def get_popover_text(%{key: "Docs"} = assigns) do
    ~H"""
    <pre>
    The link to the documentation page for the metric.
    </pre>
    """
  end

  def get_popover_text(%{key: "Has Incomplete Data"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric has incomplete data.
    Only daily metrics (metrics with Frequency of 1d or bigger) can have incomplete data.

    In some cases, if the day is not yet complete, the current value can be misleading.
    For instance, fetching daily active addresses at 12pm UTC would
    include only half a day's data, potentially making the metric value for that day appear too low.

    By default the incomplete data is not returned by the API.
    To obtain this last incomplete data point, provide the `includeIncompleteData` flag
    Example:
      {
        getMetric(metric: "daily_active_addresses"){
          timeseriesData(
            slug: "bitcoin"
            from: "utc_now-3d"
            to: "utc_now"
            <b>includeIncompleteData: true</b>){
              datetime
              value
            }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Is Timebound"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric is timebound.
    </pre>
    """
  end

  def get_popover_text(%{key: "Is Template Metric"} = assigns) do
    ~H"""
    <pre>
    A boolean that indicates whether the metric registry record is a template metric.
    A template metric is one that is used to generate multiple metrics. The template
    metric's names have {{key}} templates in them that are replaced with the values
    provided in the parameters field.
    </pre>
    """
  end

  def get_popover_text(%{key: "Parameters"} = assigns) do
    ~H"""
    <pre>
    The parameters used if the metric is a template metric.
    </pre>
    """
  end

  def get_popover_text(%{key: "Fixed Parameters"} = assigns) do
    ~H"""
    <pre>
    The fixed parameters is used to define multiple different API public metrics
    on top of a single internal metric.

    For example, the 'historical_balance_centralized_exchanges' and 'historical_balance_whales_usd'
    are defined on top of the internal 'combined_labeled_balance' metric.
    </pre>
    """
  end

  def get_popover_text(%{key: "Available Aggregations"} = assigns) do
    ~H"""
    <pre>
    The available aggregations for the metric.

    The aggregation controls how multiple data points are combined into one.

    For example, if the metric is `price_usd`, the aggregation is `LAST`, and the
    interval is `1d`, then each data point will be represented by the last price in the
    given day.


    All aggregations except `OHLC` are queried the same way:

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: MAX</b>){
            datetime
            value
          }
        }
      }

    When `OHLC` aggregation is used, the result is fetched in a different way -
    use `valueOhlc` instead of `value`:

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: OHLC</b>){
            datetime
            <b>valueOhlc {
              open high close low
            }</b>
          }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Default Aggregation"} = assigns) do
    ~H"""
    <pre>
    The default aggregation for the metric.

    The default aggregation is hand picked so it makes most sense for the given metric.

    For example, the default aggregation for `price_usd` is `LAST`, as other aggregations like
    `SUM` do not make sense for that metric.

    To override the default aggregation, provide the `aggregation` parameter.

    Example:
      {
        getMetric(metric: "price_usd"){
          timeseriesData(
          slug: "bitcoin"
          from: "utc_now-90d"
          to: "utc_now"
          <b>aggregation: MAX</b>){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Available Selectors"} = assigns) do
    ~H"""
    <pre>
    The available selectors for the metric.

    The selectors control what entity the data is fetched for.
    For example, if the metric is `price_usd`, the selector is `asset`, and the
    value is `ethereum`, then the data will be fetched for.

    To provide any selector other than `slug`, use the `selector` input parameter.

    Example:
      {
        getMetric(metric: "active_withdrawals_per_exchange"){
          timeseriesData(
          <b>selector: { slug: "bitcoin" owner: "binance" }</b>
          from: "utc_now-90d"
          to: "utc_now"){
            datetime
            value
          }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Required Selectors"} = assigns) do
    ~H"""
    <pre>
    The required selectors for the metric.

    This list includes the selectors that must be provided in order to get data.
    Not providing the required selectors will lead to an error and no data will be returned.

    Check the information for `Available Selectors` for an example.
    </pre>
    """
  end

  def get_popover_text(%{key: "Data Type"} = assigns) do
    ~H"""
    <pre>
    The data type of the metric.
    The data type is used to determine how the data is stored and fetched.

    All metrics with `timeseries` data type are fetched in a generic way using `timeseriesData` field.

    Example:
      {
        getMetric(metric: "price_usd"){
          <b>timeseriesData</b>(
            slug: "bitcoin"
            from: "utc_now-90d"
            to: "utc_now"){
              datetime
              value
            }
        }
      }

    The metrics with `histogram` data type are fetched in different ways as their result format
    could differ. Check the documentation of each such metric to see an example.
    </pre>
    """
  end

  def get_popover_text(%{key: "Available Assets"} = assigns) do
    ~H"""
    <pre>
    The assets for which the metric is available.
    The metric can be fetched for any of the listed assets.

    Each asset is uniquely identified by its `slug`:

    Example:
      {
        getMetric(metric: "daily_active_addresses"){
          timeseriesData(
            <b>slug: "bitcoin"</b>
            from: "utc_now-90d"
            to: "utc_now"){
              datetime
              value
            }
        }
      }
    </pre>
    """
  end

  def get_popover_text(%{key: "Access"} = assigns) do
    ~H"""
    <pre>
    <b>FREE</b> - The metrics labeled <b>FREE</b> have their entire historical data and realtime data
    available without any restrictions. These metrics are available to all users, regardless of their
    subscription level.

    <b>RESTRICTED</b> - The metrics labeled <b>RESTRICTED</b> have their historical and realtime data
    restricted based on the subscription plan of the user.

    To see how much of the historical and realtime data is restricted, check the restrictions
    at the <.link class="underline text-blue-600" href="https://app.santiment.net/pricing?plans=business">pricing page</.link>.
    The documentation about the restriction is avaialble at <.link class="underline text-blue-600" href="https://academy.santiment.net/sanapi/historical-and-realtime-data-restrictions">this Academy page</.link>.
    </pre>
    """
  end

  def get_popover_text(%{key: "Metric Details"} = assigns) do
    ~H"""
    <pre>
    See more details about the metric.
    </pre>
    """
  end
end
