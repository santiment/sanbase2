defmodule Sanbase.Metric.UIMetadata.DisplayOrder.Reorder do
  @moduledoc """
  This module contains functions for handling metric display order reordering operations.
  The functions are pure and take explicit inputs, making them easy to test.
  """

  alias Sanbase.Metric.UIMetadata.DisplayOrder

  @doc """
  Prepares the reordering data based on the provided metric IDs (from UI drag-and-drop)
  and the collection of metrics.

  Returns a tuple with:
  - category_id: The ID of the category being reordered
  - new_order: The list of maps with metric_id and display_order pairs to apply

  If no valid reordering can be determined, returns {:error, reason}
  """
  @spec prepare_reordering(list(String.t()), list(map())) ::
          {:ok, integer(), list(map())} | {:error, String.t()}
  def prepare_reordering(ids, metrics) when is_list(ids) and is_list(metrics) do
    # Extract filtered metrics based on the ids provided (from UI)
    filtered_metric_ids =
      ids
      |> Enum.map(fn id ->
        id
        |> String.replace("metric-", "")
        |> Integer.parse()
      end)
      |> Enum.filter(&is_tuple/1)
      |> Enum.map(fn {id, _} -> id end)

    # Get the actual metric structs for these IDs
    filtered_metrics = Enum.filter(metrics, &(&1.id in filtered_metric_ids))

    case filtered_metrics do
      [] ->
        {:error, "No metrics found matching the provided IDs"}

      metrics ->
        # Get the category ID (assume all metrics are from the same category)
        first_metric = List.first(metrics)
        category_id = first_metric.category_id

        # Get all metrics in this category, not just the filtered ones
        all_category_metrics =
          metrics
          |> Enum.filter(&(&1.category_id == category_id))
          |> Enum.sort_by(& &1.display_order)

        # Map of current display orders by metric_id for all metrics in the category
        current_orders = Map.new(all_category_metrics, fn m -> {m.id, m.display_order} end)

        # Create a mapping from metric ID to its position in the new order from UI
        new_positions =
          ids
          |> Enum.with_index()
          |> Enum.map(fn {id, index} ->
            metric_id = String.replace(id, "metric-", "")
            {id, _} = Integer.parse(metric_id)
            {id, index}
          end)
          |> Map.new()

        # Get the original display_order values for all metrics in the category
        # We need to preserve these values but assign them in the new order
        original_display_orders =
          filtered_metrics
          |> Enum.map(&Map.get(current_orders, &1.id))
          |> Enum.sort()

        # Create the new order updates based on the new positions
        # but preserving the original display_order values
        new_order =
          filtered_metrics
          |> Enum.map(fn metric ->
            position = Map.get(new_positions, metric.id, 0)
            # Use the original display_order value at this position
            new_display_order = Enum.at(original_display_orders, position)
            %{metric_id: metric.id, display_order: new_display_order}
          end)

        {:ok, category_id, new_order}
    end
  end

  @doc """
  Applies the reordering to the database.
  Takes the category_id and the new_order list of maps.
  """
  @spec apply_reordering(integer(), list(map())) :: {:ok, :ok} | {:error, any()}
  def apply_reordering(category_id, new_order) do
    DisplayOrder.reorder_metrics(category_id, new_order)
  end
end
