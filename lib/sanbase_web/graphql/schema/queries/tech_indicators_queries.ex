defmodule SanbaseWeb.Graphql.Schema.TechIndicatorsQueries do
  @moduledoc ~s"""
  Queries wrapping tech-indicators API
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.TechIndicatorsResolver
  alias SanbaseWeb.Graphql.Complexity

  alias SanbaseWeb.Graphql.Middlewares.TimeframeRestriction

  import_types(SanbaseWeb.Graphql.TechIndicatorsTypes)

  object :tech_indicators_queries do
    @desc ~s"""
    Fetch the price-volume difference technical indicator for a given ticker, display currency and time period.
    This indicator measures the difference in trend between price and volume,
    specifically when price goes up as volume goes down.
    """
    field :price_volume_diff, list_of(:price_volume_diff) do
      arg(:slug, non_null(:string))
      @desc "Currently supported currencies: USD, BTC"
      arg(:currency, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")
      arg(:size, :integer, default_value: 0)

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      cache_resolve(&TechIndicatorsResolver.price_volume_diff/3)
    end

    @desc ~s"""
    Returns pairs of datetime and metricValue, where anomaly (metricValue outside some calculated boundary) was detected for chosen metric.
    Field `metricValue` is the value from original metric that is considered abnormal.

    Arguments description:
    * metric - name of metric (currently supports DAILY_ACTIVE_ADDRESSES and DEV_ACTIVITY)
    * slug - project's slug
    * from - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * to - a string representation of datetime value according to the iso8601 standard, e.g. "2018-04-16T10:02:19Z"
    * interval - an integer followed by one of: `m`, `h`, `d`, `w`
    """
    field :metric_anomaly, list_of(:anomaly_value) do
      arg(:metric, non_null(:anomalies_metrics_enum))
      arg(:slug, non_null(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :string, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(TimeframeRestriction)
      cache_resolve(&TechIndicatorsResolver.metric_anomaly/3)
    end
  end
end
