defmodule SanbaseWeb.Graphql.Resolvers.MetricDisplayOrderResolver do
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Repo

  def get_ordered_metrics(_root, _args, _resolution) do
    ordered_data = DisplayOrder.get_ordered_metrics()

    {:ok,
     %{
       categories: ordered_data.categories |> Enum.map(& &1.name),
       metrics: ordered_data.metrics
     }}
  end

  def get_metrics_by_category(_root, %{category: category}, _resolution) do
    # Find category by name
    case Sanbase.Metric.UIMetadata.Category.by_name(category) do
      nil ->
        {:ok, []}

      category_record ->
        metrics =
          DisplayOrder.by_category(category_record.id)
          |> Enum.map(&Repo.preload(&1, [:category, :group]))
          |> Enum.map(&to_api_format/1)

        {:ok, metrics}
    end
  end

  def get_metrics_by_category_and_group(_root, %{category: category, group: group}, _resolution) do
    # Find category by name
    case Sanbase.Metric.UIMetadata.Category.by_name(category) do
      nil ->
        {:ok, []}

      category_record ->
        # Find group by name and category_id
        case Sanbase.Metric.UIMetadata.Group.by_name_and_category(group, category_record.id) do
          nil ->
            {:ok, []}

          group_record ->
            metrics =
              DisplayOrder.by_category_and_group(category_record.id, group_record.id)
              |> Enum.map(&Repo.preload(&1, [:category, :group]))
              |> Enum.map(&to_api_format/1)

            {:ok, metrics}
        end
    end
  end

  def get_recently_added_metrics(_root, %{days: days}, _resolution) do
    metrics =
      DisplayOrder.recently_added(days)
      |> Enum.map(&Repo.preload(&1, [:category, :group]))
      |> Enum.map(&to_api_format/1)

    {:ok, metrics}
  end

  def get_categories_and_groups(_root, _args, _resolution) do
    categories_and_groups = DisplayOrder.get_categories_and_groups()

    {:ok, categories_and_groups}
  end

  # Convert database record to API format
  defp to_api_format(display_order) do
    category_name = if display_order.category, do: display_order.category.name, else: nil
    group_name = if display_order.group, do: display_order.group.name, else: nil

    %{
      metric: display_order.metric,
      type: display_order.type,
      ui_human_readable_name: display_order.ui_human_readable_name,
      category_name: category_name,
      group_name: group_name,
      chart_style: display_order.chart_style,
      unit: display_order.unit,
      description: display_order.description,
      args: display_order.args,
      is_new: DisplayOrder.is_new?(display_order.inserted_at),
      display_order: display_order.display_order,
      inserted_at: display_order.inserted_at,
      updated_at: display_order.updated_at
    }
  end
end
