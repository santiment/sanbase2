defmodule Sanbase.MetricRegistry do
  @moduledoc "Metric categorization and UI display order reads for the web layer."

  alias Sanbase.Metric.Category
  alias Sanbase.Metric.UIMetadata
  alias Sanbase.Metric.UIMetadata.DisplayOrder
  alias Sanbase.Repo

  defdelegate category_ordered_metrics(), to: Category, as: :get_ordered_metrics

  defdelegate ui_category_by_name(name), to: UIMetadata.Category, as: :by_name

  defdelegate ui_group_by_name_and_category(name, category_id),
    to: UIMetadata.Group,
    as: :by_name_and_category

  defdelegate ui_display_order_ordered_metrics(), to: DisplayOrder, as: :get_ordered_metrics

  defdelegate ui_categories_and_groups(), to: DisplayOrder, as: :get_categories_and_groups

  def ui_metrics_by_category(category_id) do
    DisplayOrder.by_category(category_id) |> preload_category_and_group()
  end

  def ui_metrics_by_category_and_group(category_id, group_id) do
    DisplayOrder.by_category_and_group(category_id, group_id) |> preload_category_and_group()
  end

  def ui_recently_added_metrics(days) do
    DisplayOrder.recently_added(days) |> preload_category_and_group()
  end

  defdelegate ui_metric_new?(inserted_at), to: DisplayOrder, as: :is_new?

  defp preload_category_and_group(display_orders),
    do: Repo.preload(display_orders, [:category, :group])
end
