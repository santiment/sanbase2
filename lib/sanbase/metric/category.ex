defmodule Sanbase.Metric.Category do
  @moduledoc """
  Context module for metric categories operations.

  This module provides a public API for managing metric categories, groups,
  and their mappings following the domain-driven design principles.
  """
  import Ecto.Query

  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricGroup
  alias Sanbase.Metric.Category.MetricCategoryMapping

  def all_ordered() do
    query = from(c in MetricCategory, order_by: [asc: c.display_order])
    Sanbase.Repo.all(query)
  end

  @doc """
  Atomically swaps the `display_order` of two metric categories in a single SQL statement.

  Returns `{:ok, [lhs, rhs]}` with the updated categories, or `{:error, reason}` on failure.
  """
  @spec swap_categories_display_orders(MetricCategory.t(), MetricCategory.t()) ::
          {:ok, [MetricCategory.t()]} | {:error, any()}
  def swap_categories_display_orders(%MetricCategory{} = lhs, %MetricCategory{} = rhs) do
    MetricCategory.swap_display_orders(lhs, rhs)
  end

  @doc """
  Atomically swaps the `display_order` of two metric groups in a single SQL statement.

  Returns `{:ok, [lhs, rhs]}` with the updated groups, or `{:error, reason}` on failure.
  """
  @spec swap_groups_display_orders(MetricGroup.t(), MetricGroup.t()) ::
          {:ok, [MetricGroup.t()]} | {:error, any()}
  def swap_groups_display_orders(%MetricGroup{} = lhs, %MetricGroup{} = rhs) do
    MetricGroup.swap_display_orders(lhs, rhs)
  end

  # Category operations

  @doc """
  Creates a new metric category.
  """
  @spec create_category(map()) :: {:ok, MetricCategory.t()} | {:error, Ecto.Changeset.t()}
  def create_category(attrs) do
    MetricCategory.create(attrs)
  end

  @doc """
  Creates a metric category if it doesn't exist.
  """
  @spec create_category_if_not_exists(map()) ::
          {:ok, MetricCategory.t()}
  def create_category_if_not_exists(attrs) do
    MetricCategory.create_if_not_exists(attrs)
  end

  @doc """
  Updates a metric category.
  """
  @spec update_category(MetricCategory.t(), map()) ::
          {:ok, MetricCategory.t()} | {:error, Ecto.Changeset.t()}
  def update_category(%MetricCategory{} = category, attrs) do
    MetricCategory.update(category, attrs)
  end

  @doc """
  Deletes a metric category.
  """
  @spec delete_category(MetricCategory.t()) ::
          {:ok, MetricCategory.t()} | {:error, Ecto.Changeset.t()}
  def delete_category(%MetricCategory{} = category) do
    MetricCategory.delete(category)
  end

  @doc """
  Gets a metric category by ID.
  """
  @spec get_category(integer()) :: {:ok, MetricCategory.t()} | {:error, String.t()}
  def get_category(id) do
    case MetricCategory.get(id) do
      %MetricCategory{} = struct -> {:ok, struct}
      nil -> {:error, "Metric Category with id #{id} does not exist"}
    end
  end

  @doc """
  Lists all metric categories ordered by display order.
  """
  @spec list_categories() :: [MetricCategory.t()]
  def list_categories, do: MetricCategory.list_ordered()

  @doc """
  Lists all metric categories with their groups.
  """
  @spec list_categories_with_groups() :: [MetricCategory.t()]
  def list_categories_with_groups, do: MetricCategory.list_with_groups()

  @doc """
  Reorders categories by display order.
  """
  @spec reorder_categories([%{id: integer(), display_order: integer()}]) ::
          {:ok, :ok} | {:error, any()}
  def reorder_categories(new_order), do: MetricCategory.reorder(new_order)

  # Group operations

  @doc """
  Creates a new metric group.
  """
  @spec create_group(map()) :: {:ok, MetricGroup.t()} | {:error, Ecto.Changeset.t()}
  def create_group(attrs) do
    MetricGroup.create(attrs)
  end

  @doc """
  Updates a metric group.
  """
  @spec update_group(MetricGroup.t(), map()) ::
          {:ok, MetricGroup.t()} | {:error, Ecto.Changeset.t()}
  def update_group(%MetricGroup{} = group, attrs) do
    MetricGroup.update(group, attrs)
  end

  @doc """
  Deletes a metric group.
  """
  @spec delete_group(MetricGroup.t()) :: {:ok, MetricGroup.t()} | {:error, Ecto.Changeset.t()}
  def delete_group(%MetricGroup{} = group) do
    MetricGroup.delete(group)
  end

  @doc """
  Gets a metric group by ID.
  """
  @spec get_group(integer()) :: {:ok, MetricGroup.t()} | {:error, String.t()}
  def get_group(id) do
    case MetricGroup.get(id) do
      %MetricGroup{} = struct -> {:ok, struct}
      nil -> {:error, "Metric Group with id #{id} does not exist"}
    end
  end

  @doc """
  Lists all metric groups for a specific category.
  """
  @spec list_groups_by_category(integer()) :: [MetricGroup.t()]
  def list_groups_by_category(category_id), do: MetricGroup.list_by_category(category_id)

  @doc """
  Lists all metric groups with their category.
  """
  @spec list_groups_with_category() :: [MetricGroup.t()]
  def list_groups_with_category, do: MetricGroup.list_with_category()

  @doc """
  Creates a metric group if it doesn't exist.
  """
  @spec create_group_if_not_exists(map()) ::
          {:ok, MetricGroup.t()}
  def create_group_if_not_exists(attrs) do
    MetricGroup.create_if_not_exists(attrs)
  end

  @doc """
  Reorders groups by display order.
  """
  @spec reorder_groups([%{id: integer(), display_order: integer()}]) ::
          :ok | {:error, any()}
  def reorder_groups(new_order), do: MetricGroup.reorder(new_order)

  # Mapping operations

  @doc """
  Creates a new metric categories mapping.
  """
  @spec create_mapping(map()) :: {:ok, MetricCategoryMapping.t()} | {:error, Ecto.Changeset.t()}
  def create_mapping(attrs) do
    MetricCategoryMapping.create(attrs)
  end

  @doc """
  Updates a metric categories mapping.
  """
  @spec update_mapping(MetricCategoryMapping.t(), map()) ::
          {:ok, MetricCategoryMapping.t()} | {:error, Ecto.Changeset.t()}
  def update_mapping(%MetricCategoryMapping{} = mapping, attrs) do
    MetricCategoryMapping.update(mapping, attrs)
  end

  @doc """
  Deletes a metric categories mapping.
  """
  @spec delete_mapping(MetricCategoryMapping.t()) ::
          {:ok, MetricCategoryMapping.t()} | {:error, Ecto.Changeset.t()}
  def delete_mapping(%MetricCategoryMapping{} = mapping) do
    MetricCategoryMapping.delete(mapping)
  end

  @doc """
  Gets mappings by metric registry ID.
  """
  @spec get_mappings_by_metric_registry_id(integer()) :: [MetricCategoryMapping.t()]
  def get_mappings_by_metric_registry_id(metric_registry_id) do
    MetricCategoryMapping.get_by_metric_registry_id(metric_registry_id)
  end

  @doc """
  Gets mappings by module and metric.
  """
  @spec get_mappings_by_module_and_metric(String.t(), String.t()) :: [MetricCategoryMapping.t()]
  def get_mappings_by_module_and_metric(module, metric) do
    MetricCategoryMapping.get_by_module_and_metric(module, metric)
  end

  @doc """
  Gets mappings by group ID.
  """
  @spec get_mappings_by_group_id(integer()) :: [MetricCategoryMapping.t()]
  def get_mappings_by_group_id(group_id) do
    MetricCategoryMapping.get_by_group_id(group_id)
  end

  @doc """
  Gets metrics for a specific category and group, ordered by display_order.
  """
  @spec get_metrics_for_group(integer(), integer()) :: [MetricCategoryMapping.t()]
  def get_metrics_for_group(category_id, group_id) do
    MetricCategoryMapping.get_by_category_and_group(category_id, group_id)
  end

  @doc """
  Gets ungrouped metrics for a category, ordered by display_order.
  """
  @spec get_ungrouped_metrics(integer()) :: [MetricCategoryMapping.t()]
  def get_ungrouped_metrics(category_id) do
    MetricCategoryMapping.get_ungrouped_by_category(category_id)
  end

  @doc """
  Reorders metric category mappings.
  """
  @spec reorder_mappings([%{id: integer(), display_order: integer()}]) :: :ok | {:error, any()}
  def reorder_mappings(new_order) do
    MetricCategoryMapping.reorder_mappings(new_order)
  end

  @doc """
  Creates a mapping if it doesn't exist.
  """
  @spec create_mapping_if_not_exists(map()) ::
          {:ok, MetricCategoryMapping.t()} | {:error, Ecto.Changeset.t()}
  def create_mapping_if_not_exists(attrs) do
    MetricCategoryMapping.create_if_not_exists(attrs)
  end

  # High-level operations

  @doc """
  Creates a complete category hierarchy with groups.
  """
  @spec create_category_hierarchy(map()) :: {:ok, map()} | {:error, any()}
  def create_category_hierarchy(%{category: category_attrs, groups: groups_attrs}) do
    with {:ok, category} <- create_category(category_attrs),
         {:ok, groups} <- create_groups_for_category(groups_attrs, category.id) do
      {:ok, %{category: category, groups: groups}}
    end
  end

  @doc """
  Gets the full hierarchy of categories, groups, and their mappings.
  """
  @spec get_full_hierarchy() :: [MetricCategory.t()]
  def get_full_hierarchy do
    categories = list_categories_with_groups()
    groups_with_mappings = MetricGroup.list_with_category_and_mappings()

    # Group mappings by group_id for efficient lookup
    mappings_by_group_id =
      groups_with_mappings
      |> Enum.flat_map(& &1.mappings)
      |> Enum.group_by(& &1.group_id)

    # Update groups with their mappings
    updated_groups =
      groups_with_mappings
      |> Enum.map(fn group ->
        %{group | mappings: Map.get(mappings_by_group_id, group.id, [])}
      end)

    # Group groups by category_id
    groups_by_category_id =
      updated_groups
      |> Enum.group_by(& &1.category_id)

    # Update categories with their updated groups
    categories
    |> Enum.map(fn category ->
      %{category | groups: Map.get(groups_by_category_id, category.id, [])}
    end)
  end

  # Private functions

  defp create_groups_for_category(groups_attrs, category_id) when is_list(groups_attrs) do
    groups_attrs
    |> Enum.reduce({[], []}, fn group_attrs, {success_acc, error_acc} ->
      group_attrs = Map.put(group_attrs, :category_id, category_id)

      case create_group(group_attrs) do
        {:ok, group} -> {[group | success_acc], error_acc}
        {:error, changeset} -> {success_acc, [changeset | error_acc]}
      end
    end)
    |> case do
      {groups, []} -> {:ok, Enum.reverse(groups)}
      {_, errors} -> {:error, errors}
    end
  end
end
