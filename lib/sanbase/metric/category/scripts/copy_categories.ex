defmodule Sanbase.Metric.Category.Scripts.CopyCategories do
  @moduledoc """
  Scripts for importing metric categories and groups from production.
  """

  alias Sanbase.Metric.UIMetadata.DisplayOrder

  def run(opts \\ []) do
    with :ok <- check_non_empty(opts),
         {:ok, metadata} <- create_categories_and_groups(),
         :ok <- assign_metrics_to_categories(metadata) do
      :ok
    end
  end

  defp assign_metrics_to_categories(%{category_map: category_map, group_map: group_map}) do
    DisplayOrder.get_ordered_metrics()
    |> Map.fetch!(:metrics)
    |> Enum.reduce(%{}, fn map, acc ->
      %{group_name: group_name, category_name: category_name} = map

      next_display_order = Map.get(acc, {category_name, group_name}, 0) + 1

      category_id = category_map[category_name].id
      group_id = group_name && group_map[{category_name, group_name}].id

      case map do
        %{metric_registry_id: metric_registry_id} when is_integer(metric_registry_id) ->
          Sanbase.Metric.Category.create_mapping(%{
            metric_registry_id: metric_registry_id,
            category_id: category_id,
            group_id: group_id,
            display_order: next_display_order
          })

        %{code_module: module, metric: metric} when is_binary(module) and is_binary(metric) ->
          Sanbase.Metric.Category.create_mapping(%{
            module: module,
            metric: metric,
            category_id: category_id,
            group_id: group_id,
            display_order: next_display_order
          })
      end

      Map.put(acc, {category_name, group_name}, next_display_order)
    end)
  end

  defp create_categories_and_groups() do
    # Load the canonical UI metric display order, which groups metrics by category and group
    # UIMetricDisplayOrder is assumed to be the source of authoritative sorting
    %{categories: categories} = DisplayOrder.get_categories_and_groups()

    category_map =
      categories
      |> Enum.with_index(1)
      |> Enum.map(fn {%{name: name}, display_order} ->
        {:ok, category} =
          Sanbase.Metric.Category.create_category_if_not_exists(%{
            name: name,
            display_order: display_order
          })

        {name, category}
      end)
      |> Map.new()

    group_map =
      get_ordered_groups_per_category()
      |> Enum.map(fn {category_name, groups_list} ->
        category_id = category_map[category_name].id

        groups_list
        |> Enum.reject(&is_nil/1)
        |> Enum.with_index(1)
        |> Enum.map(fn {group_name, display_order} ->
          {:ok, group} =
            Sanbase.Metric.Category.create_group_if_not_exists(%{
              name: group_name,
              display_order: display_order,
              category_id: category_id
            })

          {{category_name, group_name}, group}
        end)
      end)
      |> List.flatten()
      |> Map.new()

    {:ok, %{category_map: category_map, group_map: group_map}}
  end

  def check_non_empty(opts) do
    case Keyword.get(opts, :force, false) do
      true ->
        :ok

      false ->
        categories = Sanbase.Metric.Category.list_categories()

        if [] == categories do
          :ok
        else
          {:error,
           """
           There are already some categories present in the new tables.
           If you still need to run the script, provide force: true param
           """}
        end
    end
  end

  defp get_ordered_groups_per_category() do
    DisplayOrder.get_ordered_metrics()
    |> Map.fetch!(:metrics)
    |> Enum.reduce(%{}, fn map, acc ->
      %{group_name: group_name, category_name: category_name} = map

      groups_list = Map.get(acc, category_name)

      cond do
        nil == groups_list ->
          # If this is the first time we encoutner this category,
          # the group is the first one in that category
          Map.put(acc, category_name, [group_name])

        group_name in groups_list ->
          acc

        true ->
          # There will be < 50 groups, so it's ok to append at the en
          Map.put(acc, category_name, groups_list ++ [group_name])
      end
    end)
  end
end
