defmodule SanbaseWeb.Graphql.Schema.MetricQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricResolver
  alias SanbaseWeb.Graphql.Middlewares.TransformResolution
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  object :metric_queries do
    @desc ~s"""
    Return data for a given metric.
    """
    field :get_metric, :metric do
      meta(access: :free)
      arg(:metric, non_null(:string))
      arg(:store_executed_clickhouse_sql, :boolean, default_value: false)

      middleware(TransformResolution)
      resolve(&MetricResolver.get_metric/3)
    end

    field :get_available_metrics, list_of(:string) do
      meta(access: :free)

      arg(:product, :products_enum, default_value: :sanapi)
      arg(:plan, :plans_enum)
      arg(:has_incomplete_data, :boolean, default_value: nil)

      @desc ~s"""
      Accepts PCRE (Perl Compatible Regular Expressions) format

      Example: { getAvailableMetrics(nameRegexFilter: "^mean_age_[\\d]+") }
      """
      arg(:name_regex_filter, :string, default_value: nil)

      cache_resolve(&MetricResolver.get_available_metrics/3,
        ttl: 300,
        # NOTE: Or, we can pass here something more custom that knows how to compute user details?
        include_user_details_in_key: true
      )
    end

    field :get_available_metrics_for_selector, list_of(:string) do
      meta(access: :free)

      arg(:selector, :metric_target_selector_input_object)

      @desc ~s"""
      Accepts PCRE (Perl Compatible Regular Expressions) format

      Example: { getAvailableMetrics(nameRegexFilter: "^mean_age_[\\d]+") }
      """
      arg(:name_regex_filter, :string, default_value: nil)

      cache_resolve(&MetricResolver.get_available_metrics_for_selector/3, ttl: 300)
    end

    field :get_latest_metric_data, list_of(:latest_metric_data) do
      deprecate("""
      This API is not intended for widespread use. \
      It will be deprecated once Websocket Subscriptions are added
      """)

      meta(access: :restricted, min_plan: [sanapi: "PRO", sanbase: "PRO"])

      arg(:selector, :metric_target_selector_input_object)
      arg(:metrics, list_of(:string))

      middleware(AccessControl)
      cache_resolve(&MetricResolver.latest_metrics_data/3, ttl: 30)
    end
  end
end
