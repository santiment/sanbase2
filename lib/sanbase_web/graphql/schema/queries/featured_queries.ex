defmodule SanbaseWeb.Graphql.Schema.FeaturedQueries do
  @moduledoc ~s"""
  Queries and mutations for working with featured insights, watchlists
  """
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.FeaturedItemResolver

  object :featured_item_queries do
    field :featured_insights, list_of(:post) do
      meta(access: :free)

      arg(:page, :integer, default_value: 1)
      arg(:page_size, :integer, default_value: 5)

      cache_resolve(&FeaturedItemResolver.insights/3)
    end

    field :featured_watchlists, list_of(:user_list) do
      meta(access: :free)
      arg(:type, :watchlist_type_enum, default_value: :project)
      cache_resolve(&FeaturedItemResolver.watchlists/3)
    end

    field :featured_screeners, list_of(:user_list) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.screeners/3)
    end

    field :featured_user_triggers, list_of(:user_trigger) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.user_triggers/3)
    end

    field :featured_chart_configurations, list_of(:chart_configuration) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.chart_configurations/3)
    end

    field :featured_table_configurations, list_of(:table_configuration) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.table_configurations/3)
    end

    field :featured_dashboards, list_of(:dashboard) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.dashboards/3)
    end

    field :featured_queries, list_of(:sql_query) do
      meta(access: :free)
      cache_resolve(&FeaturedItemResolver.queries/3)
    end
  end
end
