defmodule Sanbase.Metric.Category.MetricCategoryMapping do
  @moduledoc """
  Schema for metric categories mapping.

  This table maps metrics to categories and groups. It can reference metrics
  either by metric_registry_id or by module/metric combination.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricGroup
  alias Sanbase.Metric.UIMetadata

  @type t :: %__MODULE__{
          id: integer(),
          metric_registry_id: integer() | nil,
          metric_registry: Registry.t() | nil,
          module: String.t() | nil,
          metric: String.t() | nil,
          category: MetricCategory.t(),
          category_id: integer(),
          group: MetricGroup.t() | nil,
          group_id: integer() | nil,
          display_order: integer() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_category_mappings" do
    # Either module/metric is set and metric_registry is nil
    # or vice versa. There is a DB constaint check for that as well
    field(:module, :string)
    field(:metric, :string)

    belongs_to(:metric_registry, Registry, foreign_key: :metric_registry_id)

    belongs_to(:category, MetricCategory, foreign_key: :category_id)
    belongs_to(:group, MetricGroup, foreign_key: :group_id)

    has_many(:ui_metadata_list, UIMetadata, foreign_key: :metric_category_mapping_id)

    field(:display_order, :integer)

    timestamps()
  end

  @doc """
  Creates a changeset for metric categories mapping.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = mapping, attrs) do
    mapping
    |> cast(attrs, [
      :metric_registry_id,
      :module,
      :metric,
      :category_id,
      :group_id,
      :display_order
    ])
    |> validate_metric_reference()
    |> validate_length(:module, max: 255)
    |> validate_length(:metric, max: 255)
    |> validate_required([:category_id])
    |> foreign_key_constraint(:category_id)
    |> foreign_key_constraint(:metric_registry_id)
    |> foreign_key_constraint(:group_id)
    # The unique constraints don't apply when the field is nil.
    # Either metric_registry_id or module/metric is set.
    |> unique_constraint([:metric_registry_id, :category_id, :group_id],
      name: :metric_category_mappings_metric_registry_id_category_id_group_i
    )
    |> unique_constraint([:module, :metric, :category_id, :group_id],
      name: :metric_category_mappings_module_metric_category_id_group_id_ind
    )
  end

  @doc """
  Creates a new metric categories mapping.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a metric categories mapping.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = mapping, attrs) do
    mapping
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a metric categories mapping.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = mapping) do
    Repo.delete(mapping)
  end

  @doc """
  Gets a metric categories mapping by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    query =
      from(m in __MODULE__,
        where: m.id == ^id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.one(query)
  end

  @doc """
  Gets a metric categories mapping by metric_registry_id
  """
  @spec get_by_metric_registry_id(integer()) :: t() | nil
  def get_by_metric_registry_id(metric_registry_id) when is_integer(metric_registry_id) do
    query =
      from(m in __MODULE__,
        where: m.metric_registry_id == ^metric_registry_id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.one(query)
  end

  @doc """
  Gets a metric categories mapping by module and metric
  """
  @spec get_by_module_and_metric(String.t(), String.t()) :: t() | nil
  def get_by_module_and_metric(module, metric) when is_binary(module) and is_binary(metric) do
    query =
      from(m in __MODULE__,
        where: m.module == ^module and m.metric == ^metric,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.one(query)
  end

  @doc """
  Gets mappings by metric registry ID.
  """
  @spec get_by_metric_registry_id(integer()) :: [t()]
  def get_by_metric_registry_id(metric_registry_id) when is_integer(metric_registry_id) do
    query =
      from(m in __MODULE__,
        where: m.metric_registry_id == ^metric_registry_id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.one(query)
  end

  @doc """
  Gets mappings by module and metric.
  """
  @spec get_by_module_and_metric(String.t(), String.t()) :: [t()]
  def get_by_module_and_metric(module, metric) when is_binary(module) and is_binary(metric) do
    query =
      from(m in __MODULE__,
        where: m.module == ^module and m.metric == ^metric,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.one(query)
  end

  @doc """
  Gets mappings by group ID.
  """
  @spec get_by_category_id(integer()) :: [t()]
  def get_by_category_id(category_id) when is_integer(category_id) do
    query =
      from(m in __MODULE__,
        where: m.category_id == ^category_id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.all(query)
  end

  @doc """
  Gets mappings by group ID.
  """
  @spec get_by_group_id(integer()) :: [t()]
  def get_by_group_id(group_id) when is_integer(group_id) do
    query =
      from(m in __MODULE__,
        where: m.group_id == ^group_id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.all(query)
  end

  @doc """
  Gets mappings for a specific category and group, ordered by display_order.
  """
  @spec get_by_category_and_group(integer(), integer()) :: [t()]
  def get_by_category_and_group(category_id, group_id)
      when is_integer(category_id) and is_integer(group_id) do
    query =
      from(m in __MODULE__,
        where: m.category_id == ^category_id and m.group_id == ^group_id,
        preload: [:category, :group, :metric_registry, :ui_metadata_list],
        order_by: [asc: m.display_order, asc: m.id]
      )

    Repo.all(query)
  end

  @doc """
  Gets ungrouped mappings for a category (where group_id is nil), ordered by display_order.
  """
  @spec get_ungrouped_by_category(integer()) :: [t()]
  def get_ungrouped_by_category(category_id) when is_integer(category_id) do
    query =
      from(m in __MODULE__,
        where: m.category_id == ^category_id and is_nil(m.group_id),
        preload: [:category, :group, :metric_registry, :ui_metadata_list],
        order_by: [asc: m.display_order, asc: m.id]
      )

    Repo.all(query)
  end

  @doc """
  Lists all metric categories mappings with their related data.
  """
  @spec list_all() :: [t()]
  def list_all do
    query =
      from(m in __MODULE__,
        preload: [:category, :group, :metric_registry, :ui_metadata_list]
      )

    Repo.all(query)
  end

  @doc """
  Creates a mapping by metric registry ID.
  """
  @spec create_by_metric_registry_id(integer(), integer() | nil, integer() | nil) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_by_metric_registry_id(metric_registry_id, category_id, group_id)
      when is_integer(metric_registry_id) do
    create(%{
      metric_registry_id: metric_registry_id,
      category_id: category_id,
      group_id: group_id
    })
  end

  @doc """
  Creates a mapping by module and metric.
  """
  @spec create_by_module_and_metric(String.t(), String.t(), integer() | nil, integer() | nil) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_by_module_and_metric(module, metric, category_id, group_id)
      when is_binary(module) and is_binary(metric) do
    create(%{
      module: module,
      metric: metric,
      category_id: category_id,
      group_id: group_id
    })
  end

  @doc """
  Creates a mapping if it doesn't exist already.
  """
  @spec create_if_not_exists(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_if_not_exists(attrs) do
    case find_existing_mapping(attrs) do
      nil -> create(attrs)
      existing -> {:ok, existing}
    end
  end

  @doc """
  Reorders metric category mappings by updating their display_order.

  The new_order parameter should be a list of maps with mapping ID and display_order keys.
  """
  @spec reorder_mappings([%{id: integer(), display_order: integer()}]) :: :ok | {:error, any()}
  def reorder_mappings(new_order) when is_list(new_order) do
    Repo.transaction(fn -> Enum.each(new_order, &update_mapping_order/1) end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  # Private functions

  defp update_mapping_order(%{id: id, display_order: display_order}) do
    case get(id) do
      nil ->
        Repo.rollback("Mapping with ID #{id} not found")

      mapping ->
        case __MODULE__.update(mapping, %{display_order: display_order}) do
          {:ok, _} -> :ok
          {:error, error} -> Repo.rollback(error)
        end
    end
  end

  defp validate_metric_reference(changeset) do
    metric_registry_id = get_field(changeset, :metric_registry_id)
    module = get_field(changeset, :module)
    metric = get_field(changeset, :metric)

    if valid_metric_reference?(metric_registry_id, module, metric) do
      changeset
    else
      add_validation_error(changeset, metric_registry_id, module, metric)
    end
  end

  defp valid_metric_reference?(metric_registry_id, module, metric) do
    # Valid: metric_registry_id is set, module and metric are nil
    # Valid: metric_registry_id is nil, both module and metric are set
    is_metric_registry? = not is_nil(metric_registry_id) and is_nil(module) and is_nil(metric)
    is_module_metric? = is_nil(metric_registry_id) and not is_nil(module) and not is_nil(metric)

    is_metric_registry? or is_module_metric?
  end

  defp add_validation_error(changeset, metric_registry_id, module, metric) do
    cond do
      not is_nil(metric_registry_id) and (not is_nil(module) or not is_nil(metric)) ->
        add_error(changeset, :metric_registry_id, "cannot be set when module/metric are also set")

      not is_nil(module) and is_nil(metric) ->
        add_error(changeset, :metric, "must be set when module is set")

      is_nil(module) and not is_nil(metric) ->
        add_error(changeset, :module, "must be set when metric is set")

      true ->
        add_error(
          changeset,
          :base,
          "either metric_registry_id or both module and metric must be set"
        )
    end
  end

  defp find_existing_mapping(attrs) do
    cond do
      attrs[:metric_registry_id] ->
        get_by_metric_registry_id(attrs[:metric_registry_id])
        |> Enum.find(fn mapping -> mapping.group_id == attrs[:group_id] end)

      attrs[:module] && attrs[:metric] ->
        get_by_module_and_metric(attrs[:module], attrs[:metric])
        |> Enum.find(fn mapping -> mapping.group_id == attrs[:group_id] end)

      true ->
        nil
    end
  end
end
