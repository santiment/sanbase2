defmodule SanbaseWeb.Graphql.Schema.MetricCatalogQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricCatalogResolver

  object :metric_catalog_queries do
    @desc ~s"""
    The public metrics directory: every metric the API exposes, with its human
    readable name, category, refresh cadence and documentation link, searchable
    and paginated.

    Compared to the alternatives:
    - `getAvailableMetrics` returns metric names only, so rendering a listing
      with it needs one `getMetric` call per row;
    - `getOrderedMetrics` returns the Sanbase charts taxonomy, which covers only
      a subset of the metrics.

    Example:

      {
        getMetricCatalog(searchTerm: "whale", categories: ["On-chain Labels"], page: 1, pageSize: 80) {
          totalCount
          metrics {
            metric
            humanReadableName
            categoryName
            groupName
            minInterval
            docs { link }
          }
        }
      }
    """
    field :get_metric_catalog, :metric_catalog do
      meta(access: :free)

      @desc ~s"""
      Case insensitive substring, matched against both the metric name and the
      human readable name.
      """
      arg(:search_term, :string)

      @desc "Keep only the metrics in these categories, matched by name."
      arg(:categories, list_of(non_null(:string)))

      @desc "Keep only the metrics in these groups, matched by name."
      arg(:groups, list_of(non_null(:string)))

      @desc "Include the deprecated metrics in the result."
      arg(:include_deprecated, :boolean, default_value: false)

      arg(:page, :integer, default_value: 1)

      @desc "The number of metrics per page. Capped at 500."
      arg(:page_size, :integer, default_value: 80)

      cache_resolve(&MetricCatalogResolver.get_metric_catalog/3, ttl: 300)
    end

    @desc ~s"""
    The categories and groups of the metrics directory, each with the number of
    metrics in it. Used to render the category tabs and the groups dropdown.

    The counts are computed from the same metrics that `getMetricCatalog`
    returns, so passing the same `searchTerm`/`includeDeprecated` here keeps the
    tab counts consistent with the listing.
    """
    field :get_metric_catalog_categories, list_of(:metric_catalog_category) do
      meta(access: :free)

      arg(:search_term, :string)
      arg(:include_deprecated, :boolean, default_value: false)

      cache_resolve(&MetricCatalogResolver.get_metric_catalog_categories/3, ttl: 300)
    end
  end
end
