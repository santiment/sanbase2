defmodule Sanbase.Metric.Category.MetricGroup do
  @moduledoc """
  Schema for metric groups.

  Groups are organizational units within categories that contain related metrics.
  Each group belongs to a category.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          short_description: String.t() | nil,
          description: String.t() | nil,
          display_order: integer() | nil,
          category_id: integer(),
          category: MetricCategory.t() | nil,
          mappings: [MetricCategoryMapping.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_groups" do
    field(:name, :string)
    field(:short_description, :string)
    field(:description, :string)
    field(:display_order, :integer)

    belongs_to(:category, MetricCategory)
    has_many(:mappings, MetricCategoryMapping, foreign_key: :group_id)

    timestamps()
  end

  @doc """
  Creates a changeset for metric group.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = group, attrs) do
    group
    |> cast(attrs, [:name, :short_description, :description, :display_order, :category_id])
    |> validate_required([:name, :display_order, :category_id])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:short_description, max: 500)
    |> validate_length(:description, max: 2000)
    |> validate_number(:display_order, greater_than_or_equal_to: 0)
    |> foreign_key_constraint(:category_id)
    |> unique_constraint([:name, :category_id])
  end

  @doc """
  Creates a new metric group.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert(on_conflict: :nothing)
  end

  @doc """
  Updates a metric group.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = group, attrs) do
    group
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a metric group.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = group) do
    Repo.delete(group)
  end

  @doc """
  Gets a metric group by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets a metric group by name and category ID.
  """
  @spec get_by_name_and_category(String.t(), integer()) :: t() | nil
  def get_by_name_and_category(name, category_id)
      when is_binary(name) and is_integer(category_id) do
    Repo.get_by(__MODULE__, name: name, category_id: category_id)
  end

  @doc """
  Lists all metric groups for a specific category ordered by display_order.
  """
  @spec list_by_category(integer()) :: [t()]
  def list_by_category(category_id) when is_integer(category_id) do
    query =
      from(g in __MODULE__,
        where: g.category_id == ^category_id,
        order_by: [asc: g.display_order, asc: g.name]
      )

    Repo.all(query)
  end

  @doc """
  Lists all metric groups with their category.
  """
  @spec list_with_category() :: [t()]
  def list_with_category do
    query =
      from(g in __MODULE__,
        preload: [:category],
        order_by: [asc: g.display_order, asc: g.name]
      )

    Repo.all(query)
  end

  @doc """
  Lists all metric groups with their category and mappings.
  """
  @spec list_with_category_and_mappings() :: [t()]
  def list_with_category_and_mappings do
    query =
      from(g in __MODULE__,
        preload: [:category, :mappings],
        order_by: [asc: g.display_order, asc: g.name]
      )

    Repo.all(query)
  end

  @doc """
  Creates a metric group if it doesn't exist already.
  """
  @spec create_if_not_exists(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_if_not_exists(attrs) do
    case get_by_name_and_category(Map.fetch!(attrs, :name), Map.fetch!(attrs, :category_id)) do
      nil ->
        case create(attrs) do
          {:ok, group} -> {:ok, group}
          {:error, changeset} -> {:error, changeset}
        end

      existing ->
        {:ok, existing}
    end
  end

  @doc """
  Swap the display orders of both groups
  """
  @spec swap_display_orders(t(), t()) :: {:ok, [t()]} | {:error, String.t()}
  def swap_display_orders(
        %__MODULE__{display_order: lhs_order} = lhs,
        %__MODULE__{display_order: rhs_order} = rhs
      ) do
    Ecto.Multi.new()
    |> Ecto.Multi.run(:put_lhs, fn _repo, _changes ->
      __MODULE__.update(lhs, %{display_order: rhs_order})
    end)
    |> Ecto.Multi.run(:put_rhs, fn _repo, _changes ->
      __MODULE__.update(rhs, %{display_order: lhs_order})
    end)
    |> Sanbase.Repo.transaction()
    |> case do
      {:ok, %{put_lhs: new_lhs, put_rhs: new_rhs}} -> {:ok, [new_lhs, new_rhs]}
      {:error, _name, reason, _changes_so_far} -> {:error, reason}
    end
  end

  @doc """
  Updates the display order of groups.

  The new_order parameter should be a list of maps with group ID and display_order keys.
  """
  @spec reorder([%{id: integer(), display_order: integer()}]) :: {:ok, :ok} | {:error, any()}
  def reorder(new_order) when is_list(new_order) do
    Repo.transaction(fn -> Enum.each(new_order, &update_group_order/1) end)
    |> case do
      {:ok, _} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp update_group_order(%{id: id, display_order: display_order}) do
    case get(id) do
      nil ->
        Repo.rollback("Group with ID #{id} not found")

      group ->
        case __MODULE__.update(group, %{display_order: display_order}) do
          {:ok, _} -> :ok
          {:error, error} -> Repo.rollback(error)
        end
    end
  end
end
