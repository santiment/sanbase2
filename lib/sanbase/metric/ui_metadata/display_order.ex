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
  @allowed_metric_types ["metric", "query"]

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
          type: String.t(),
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
    field(:type, :string, default: "metric")

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
      :args,
      :type
    ])
    |> validate_required([:category_id, :display_order])
    |> validate_inclusion(:source_type, ["registry", "code"])
    |> validate_inclusion(:type, @allowed_metric_types)
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
    categories = Category.all_ordered()

    category_order_map =
      Map.new(categories, fn category -> {category.id, category.display_order} end)

    metrics =
      Repo.all(
        from(m in __MODULE__,
          preload: [:category, :group, :metric_registry]
        )
      )

    Enum.sort_by(metrics, fn metric ->
      category_position = Map.get(category_order_map, metric.category_id, 999)
      {category_position, metric.display_order}
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
    metrics_ids = Enum.map(new_order, & &1.metric_id)

    metrics =
      Repo.all(
        from(m in __MODULE__,
          where: m.id in ^metrics_ids and m.category_id == ^category_id,
          select: m.id
        )
      )

    if length(metrics) != length(metrics_ids) do
      {:error, "Some metrics don't exist or are not in the specified category"}
    else
      multi =
        Enum.reduce(new_order, Ecto.Multi.new(), fn %{metric_id: id, display_order: order},
                                                    multi ->
          Ecto.Multi.update_all(
            multi,
            "update_#{id}",
            from(m in __MODULE__, where: m.id == ^id),
            set: [display_order: order]
          )
        end)

      case Repo.transaction(multi) do
        {:ok, _results} ->
          {:ok, :ok}

        {:error, failed_operation, failed_value, _changes_so_far} ->
          {:error, "Failed on #{failed_operation}: #{inspect(failed_value)}"}
      end
    end
  end

  @doc """
  Get the ordered list of all metrics with their metadata.
  This combines data from both the metric registry and the display order table.
  """
  def get_ordered_metrics do
    ordered_metrics = all_ordered()

    categories = Category.all_ordered()
    ordered_category_data = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

    registry_metrics =
      Registry.all()
      |> Registry.resolve()
      |> Enum.reduce(%{}, fn registry, acc ->
        Map.put(acc, registry.metric, registry)
      end)

    metrics =
      Enum.map(ordered_metrics, fn display_order ->
        metric = display_order.metric

        registry_metric = Map.get(registry_metrics, metric)

        category_name = if display_order.category, do: display_order.category.name, else: nil
        group_name = if display_order.group, do: display_order.group.name, else: nil

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
          display_order: display_order.display_order,
          inserted_at: display_order.inserted_at,
          updated_at: display_order.updated_at,
          type: display_order.type
        }
      end)

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
    type = Keyword.get(opts, :type, "metric")

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

    {source_type, code_module, metric_registry_id} =
      if source_type do
        {source_type, code_module, metric_registry_id}
      else
        metric = if registry_metric, do: registry_metric, else: metric_name
        {s_type, c_module, m_registry_id} = determine_metric_source(metric)

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
      args: args,
      type: type
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
  Get all available metric types.
  """
  def get_available_metric_types do
    @allowed_metric_types
  end

  @doc """
  Get all categories and their groups.
  Returns a map with:
  - categories: ordered list of categories
  - groups_by_category: map of category to list of groups
  """
  def get_categories_and_groups do
    categories = Category.all_ordered()
    ordered_categories = Enum.map(categories, fn cat -> %{id: cat.id, name: cat.name} end)

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

  defp determine_metric_source(metric) do
    try do
      case Registry.by_name(metric) do
        {:ok, registry} ->
          {"registry", nil, registry.id}

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
      _ -> {"code", nil, nil}
    end
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
