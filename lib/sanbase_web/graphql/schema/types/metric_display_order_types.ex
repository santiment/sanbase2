defmodule SanbaseWeb.Graphql.MetricDisplayOrderTypes do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 2]

  alias SanbaseWeb.Graphql.Resolvers.MetricDisplayOrderResolver

  object :metric_display_order do
    field(:metric, non_null(:string))
    field(:type, :string)
    field(:ui_human_readable_name, :string)
    field(:ui_key, :string)
    field(:category_name, :string)
    field(:group_name, :string)
    field(:chart_style, :string)
    field(:unit, :string)
    field(:description, :string)
    field(:args, :json)
    field(:is_new, :boolean)
    field(:display_order, :integer)
    field(:inserted_at, :datetime)
    field(:updated_at, :datetime)
  end

  object :metric_categories_and_metrics do
    field(:categories, list_of(:string))
    field(:metrics, list_of(:metric_display_order))
  end

  object :metric_display_order_queries do
    @desc ~s"""
    Get all metrics with their display order information, organized by categories.
    """
    field :get_ordered_metrics, :metric_categories_and_metrics do
      meta(access: :free)
      cache_resolve(&MetricDisplayOrderResolver.get_ordered_metrics/3, ttl: 300)
    end

    @desc ~s"""
    Get metrics for a specific category.
    """
    field :get_metrics_by_category, list_of(:metric_display_order) do
      meta(access: :free)
      arg(:category, non_null(:string))
      cache_resolve(&MetricDisplayOrderResolver.get_metrics_by_category/3, ttl: 300)
    end

    @desc ~s"""
    Get metrics for a specific category and group.
    """
    field :get_metrics_by_category_and_group, list_of(:metric_display_order) do
      meta(access: :free)
      arg(:category, non_null(:string))
      arg(:group, non_null(:string))
      cache_resolve(&MetricDisplayOrderResolver.get_metrics_by_category_and_group/3, ttl: 300)
    end

    @desc ~s"""
    Get recently added metrics.
    """
    field :get_recently_added_metrics, list_of(:metric_display_order) do
      meta(access: :free)
      arg(:days, :integer, default_value: 14)
      cache_resolve(&MetricDisplayOrderResolver.get_recently_added_metrics/3, ttl: 300)
    end

    @desc ~s"""
    Get all categories and their groups.
    """
    field :get_categories_and_groups, :json do
      meta(access: :free)
      cache_resolve(&MetricDisplayOrderResolver.get_categories_and_groups/3, ttl: 300)
    end
  end
end
