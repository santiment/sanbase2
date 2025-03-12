defmodule SanbaseWeb.Graphql.Resolvers.MetricDisplayOrderResolver do
  alias Sanbase.Metric.DisplayOrder

  def get_ordered_metrics(_root, _args, _resolution) do
    ordered_data = DisplayOrder.get_ordered_metrics()

    {:ok,
     %{
       categories: ordered_data.categories,
       metrics: ordered_data.metrics
     }}
  end

  def get_metrics_by_category(_root, %{category: category}, _resolution) do
    metrics = DisplayOrder.by_category(category)

    # Transform the metrics to match the GraphQL type
    metrics =
      Enum.map(metrics, fn metric ->
        %{
          metric: metric.metric,
          label: metric.label,
          category: metric.category,
          group: metric.group,
          style: metric.style,
          format: metric.format,
          description: metric.description,
          source_type: metric.source_type,
          source_id: metric.source_id,
          added_at: metric.added_at,
          is_new: DisplayOrder.is_new?(metric.added_at),
          display_order: metric.display_order
        }
      end)

    {:ok, metrics}
  end

  def get_metrics_by_category_and_group(_root, %{category: category, group: group}, _resolution) do
    metrics = DisplayOrder.by_category_and_group(category, group)

    # Transform the metrics to match the GraphQL type
    metrics =
      Enum.map(metrics, fn metric ->
        %{
          metric: metric.metric,
          label: metric.label,
          category: metric.category,
          group: metric.group,
          style: metric.style,
          format: metric.format,
          description: metric.description,
          source_type: metric.source_type,
          source_id: metric.source_id,
          added_at: metric.added_at,
          is_new: DisplayOrder.is_new?(metric.added_at),
          display_order: metric.display_order
        }
      end)

    {:ok, metrics}
  end

  def get_recently_added_metrics(_root, %{days: days}, _resolution) do
    metrics = DisplayOrder.recently_added(days)

    # Transform the metrics to match the GraphQL type
    metrics =
      Enum.map(metrics, fn metric ->
        %{
          metric: metric.metric,
          label: metric.label,
          category: metric.category,
          group: metric.group,
          style: metric.style,
          format: metric.format,
          description: metric.description,
          source_type: metric.source_type,
          source_id: metric.source_id,
          added_at: metric.added_at,
          # These are all new by definition
          is_new: true,
          display_order: metric.display_order
        }
      end)

    {:ok, metrics}
  end

  def get_categories_and_groups(_root, _args, _resolution) do
    categories_and_groups = DisplayOrder.get_categories_and_groups()

    {:ok, categories_and_groups}
  end
end
