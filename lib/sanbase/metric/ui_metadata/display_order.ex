defmodule Sanbase.Metric.UIMetadata.DisplayOrder do
  use Ecto.Schema

  require Logger

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.UIMetadata.Category
  alias Sanbase.Metric.UIMetadata.Group
  alias Sanbase.Metric.UIMetadata.MetricsImporter

  @allowed_chart_styles ["filledLine", "greenRedBar", "bar", "line", "area", "reference"]
  @allowed_unit_formats ["", "usd", "percent"]

  @type t :: %__MODULE__{
          id: integer(),
          metric: String.t(),
          registry_metric: String.t(),
          category_id: integer(),
          group_id: integer(),
          display_order: integer(),
          source_type: String.t(),
          code_module: String.t(),
          metric_registry_id: integer(),
          ui_human_readable_name: String.t(),
          chart_style: String.t(),
          unit: String.t(),
          description: String.t(),
          args: map(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_display_order" do
    field(:metric, :string)
    field(:registry_metric, :string)
    field(:ui_human_readable_name, :string)
    field(:chart_style, :string, default: "line")
    field(:unit, :string, default: "")
    field(:description, :string)
    field(:args, :map, default: %{})

    field(:display_order, :integer)

    field(:source_type, :string, default: "code")
    field(:code_module, :string)

    belongs_to(:category, Category)
    belongs_to(:group, Group)
    belongs_to(:metric_registry, Sanbase.Metric.Registry)

    timestamps()
  end

  def changeset(%__MODULE__{} = display_order, attrs) do
    display_order
    |> cast(attrs, [
      :metric,
      :registry_metric,
      :category_id,
      :group_id,
      :display_order,
      :source_type,
      :code_module,
      :metric_registry_id,
      :ui_human_readable_name,
      :chart_style,
      :unit,
      :description,
      :args
    ])
    |> validate_required([:category_id, :display_order])
    |> validate_inclusion(:source_type, ["registry", "code"])
    |> validate_code_module()
  end

  # Ensure code_module is either nil or a valid string
  defp validate_code_module(changeset) do
    case get_change(changeset, :code_module) do
      nil -> changeset
      module when is_binary(module) -> changeset
      _other -> put_change(changeset, :code_module, nil)
    end
  end

  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  def do_update(%__MODULE__{} = display_order, attrs) do
    display_order
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Increment the display_order of a record by its ID.
  """
  def increment_display_order(id) when is_integer(id) do
    case by_id(id) do
      nil ->
        {:error, "Record not found"}

      record ->
        updated_attrs = %{display_order: record.display_order + 1}
        do_update(record, updated_attrs)
    end
  end

  @doc """
  Decrement the display_order of a record by its ID.
  """
  def decrement_display_order(id) when is_integer(id) do
    case by_id(id) do
      nil ->
        {:error, "Record not found"}

      record ->
        updated_attrs = %{display_order: record.display_order - 1}
        do_update(record, updated_attrs)
    end
  end

  def delete(%__MODULE__{} = display_order) do
    Repo.delete(display_order)
  end

  def by_metric(metric) do
    Repo.get_by(__MODULE__, metric: metric)
    |> Repo.preload(:category)
    |> Repo.preload(:group)
  end

  @doc """
  Get a display order record by ID.
  """
  def by_id(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
    |> Repo.preload(:category)
    |> Repo.preload(:group)
  end

  def all do
    Repo.all(__MODULE__)
  end

  @doc """
  Get all categories from the database.
  Returns a list of category names.
  """
  def categories do
    Repo.all(from(c in Category, order_by: [asc: c.display_order], select: c.name))
  end

  @doc """
  Get all metric display order entries ordered by category, group, and display_order.
  """
  def all_ordered do
    # Get all categories with their ordering
    categories = Category.all_ordered()

    category_order_map =
      Map.new(categories, fn category -> {category.id, category.display_order} end)

    # Get all metrics with preloaded category and group
    metrics =
      Repo.all(
        from(m in __MODULE__,
          preload: [:category, :group]
        )
      )

    # Sort metrics by category display_order, then group, then metric display_order
    Enum.sort_by(metrics, fn metric ->
      category_position = Map.get(category_order_map, metric.category_id, 999)
      group_name = if metric.group, do: metric.group.name, else: ""
      {category_position, group_name, metric.display_order}
    end)
  end

  @doc """
  Get all metric display order entries for a specific category.
  """
  def by_category(category_id) do
    query =
      from(m in __MODULE__,
        where: m.category_id == ^category_id,
        order_by: [asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Get all metric display order entries for a specific category and group.
  """
  def by_category_and_group(category_id, group_id) do
    query =
      from(m in __MODULE__,
        where: m.category_id == ^category_id and m.group_id == ^group_id,
        order_by: [asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Get all metrics that were added in the last n days.
  """
  def recently_added(days \\ 14) do
    date = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

    query =
      from(m in __MODULE__,
        where: m.inserted_at > ^date,
        order_by: [asc: m.category_id, asc: m.group_id, asc: m.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Reorder metrics within a category.
  The new_order parameter should be a list of maps with metric_id and display_order keys.
  """
  def reorder_metrics(category_id, new_order) do
    Repo.transaction(fn ->
      # Process each metric in the new order
      Enum.each(new_order, fn %{metric_id: metric_id, display_order: new_display_order} ->
        # Find the metric in the database by ID
        case Repo.get(__MODULE__, metric_id) do
          nil ->
            Repo.rollback("Metric with ID #{metric_id} not found")

          %__MODULE__{} = record ->
            # Check if the metric is in the correct category
            if record.category_id != category_id do
              Repo.rollback(
                "Metric with ID #{metric_id} is not in category with ID #{category_id}"
              )
            else
              # Update the display order - using Repo.update directly within transaction
              changeset = changeset(record, %{display_order: new_display_order})

              case Repo.update(changeset) do
                {:ok, _} -> :ok
                {:error, error} -> Repo.rollback(error)
              end
            end
        end
      end)

      :ok
    end)
  end

  @doc """
  Get the ordered list of all metrics with their metadata.
  This combines data from both the metric registry and the display order table.
  """
  def get_ordered_metrics do
    ordered_metrics = all_ordered()

    # Get categories in order
    categories = Category.all_ordered()
    ordered_category_data = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

    # Create a map of metric names to their registry entries
    registry_metrics =
      Registry.all()
      |> Registry.resolve()
      |> Enum.reduce(%{}, fn registry, acc ->
        Map.put(acc, registry.metric, registry)
      end)

    # Combine the data
    metrics =
      Enum.map(ordered_metrics, fn display_order ->
        metric = display_order.metric

        # Try to get the metric from the registry
        registry_metric = Map.get(registry_metrics, metric)

        # Get category and group info
        category_name = if display_order.category, do: display_order.category.name, else: nil
        group_name = if display_order.group, do: display_order.group.name, else: nil

        # Create the metric map with metadata, preferring values from display_order
        # but falling back to registry if available
        %{
          id: display_order.id,
          metric: metric,
          registry_metric: registry_metric,
          ui_human_readable_name: display_order.ui_human_readable_name || metric,
          category_id: display_order.category_id,
          category_name: category_name,
          group_id: display_order.group_id,
          group_name: group_name,
          chart_style: display_order.chart_style || "line",
          unit: display_order.unit || "",
          description: display_order.description || "",
          source_type: display_order.source_type,
          code_module: display_order.code_module,
          metric_registry_id: display_order.metric_registry_id,
          args: display_order.args || %{},
          is_new: is_new?(display_order.inserted_at),
          display_order: display_order.display_order
        }
      end)

    # Return both the metrics and the ordered categories
    %{
      metrics: metrics,
      categories: ordered_category_data
    }
  end

  @doc """
  Add a single metric to the display order table.
  This will assign a unique display_order value that is higher than any existing value.
  """
  def add_metric(metric_name, category_id, group_id \\ nil, opts \\ []) do
    ui_human_readable_name = Keyword.get(opts, :ui_human_readable_name, metric_name)
    chart_style = Keyword.get(opts, :chart_style, "line")
    unit = Keyword.get(opts, :unit, "")
    description = Keyword.get(opts, :description, "")
    args = Keyword.get(opts, :args, %{})
    source_type = Keyword.get(opts, :source_type)

    # Handle the case where Sanbase.Metric.get_module might return a non-string value
    code_module_value = Sanbase.Metric.get_module(metric_name)

    code_module =
      if is_binary(code_module_value) or is_nil(code_module_value),
        do: code_module_value,
        else: inspect(code_module_value)

    metric_registry_id = Keyword.get(opts, :metric_registry_id)
    registry_metric = Keyword.get(opts, :registry_metric)

    max_display_order =
      case Repo.one(
             from(m in __MODULE__,
               where: m.category_id == ^category_id,
               select: max(m.display_order)
             )
           ) do
        nil -> 0
        max -> max
      end

    # Determine source type and registry ID if not provided
    {source_type, code_module, metric_registry_id} =
      if source_type do
        {source_type, code_module, metric_registry_id}
      else
        metric = if registry_metric, do: registry_metric, else: metric_name
        {s_type, c_module, m_registry_id} = determine_metric_source(metric)

        # Ensure code_module is a string or nil
        normalized_code_module =
          case c_module do
            nil -> nil
            mod when is_binary(mod) -> mod
            other -> inspect(other)
          end

        {s_type, normalized_code_module, m_registry_id}
      end

    attrs = %{
      metric: metric_name,
      category_id: category_id,
      group_id: group_id,
      display_order: max_display_order + 1,
      source_type: source_type,
      code_module: code_module,
      metric_registry_id: metric_registry_id,
      registry_metric: registry_metric,
      ui_human_readable_name: ui_human_readable_name,
      chart_style: chart_style,
      unit: unit,
      description: description,
      args: args
    }

    create(attrs)
  end

  @doc """
  Check if a metric was added recently (within the specified number of days).
  """
  def is_new?(inserted_at, days \\ 14) do
    case inserted_at do
      nil ->
        false

      date ->
        threshold = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60, :second)

        # Convert NaiveDateTime to DateTime if needed
        date_with_timezone =
          case date do
            %NaiveDateTime{} ->
              DateTime.from_naive!(date, "Etc/UTC")

            %DateTime{} ->
              date
          end

        DateTime.compare(date_with_timezone, threshold) == :gt
    end
  end

  @doc """
  Get all available chart styles from the registry.
  """
  def get_available_chart_styles do
    @allowed_chart_styles
  end

  @doc """
  Get all available value formats from the registry.
  """
  def get_available_formats do
    @allowed_unit_formats
  end

  @doc """
  Get all categories and their groups.
  Returns a map with:
  - categories: ordered list of categories
  - groups_by_category: map of category to list of groups
  """
  def get_categories_and_groups do
    # Get categories in order
    categories = Category.all_ordered()
    ordered_categories = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

    # Get all groups by category
    groups_by_category =
      Enum.reduce(categories, %{}, fn category, acc ->
        groups = Group.by_category(category.id)
        group_data = Enum.map(groups, fn g -> %{id: g.id, name: g.name} end)
        Map.put(acc, category.id, group_data)
      end)

    %{
      categories: ordered_categories,
      groups_by_category: groups_by_category
    }
  end

  # Determine if a metric is from the registry or defined in code
  defp determine_metric_source(metric) do
    try do
      case Registry.by_name(metric) do
        {:ok, registry} ->
          {"registry", nil, registry.id}

        # Default to code
        {:error, _} ->
          module = Sanbase.Metric.get_module(metric)

          code_module =
            case module do
              nil -> nil
              mod when is_binary(mod) -> mod
              other -> inspect(other)
            end

          {"code", code_module, nil}
      end
    rescue
      # If there's an error (like missing columns in the registry table), default to code
      _ -> {"code", nil, nil}
    end
  end

  # Helper function to get value from registry if available, otherwise from display_order
  defp get_preferred_value(registry_metric, field, display_order_value) do
    registry_value = get_in(registry_metric || %{}, [Access.key(field)])

    if registry_value, do: registry_value, else: display_order_value
  end

  @doc """
  Import categories and groups from the metrics JSON file.
  This function should be called during application startup or as a migration.

  Returns {:ok, %{inserted: count, existing: existing_count, failed: failed_count, ...}} on success
  or {:error, reason} on failure.
  """
  def import_from_json_file(file_path \\ "ui_metrics_metadata.json") do
    MetricsImporter.import_from_file(file_path)
  end
end
