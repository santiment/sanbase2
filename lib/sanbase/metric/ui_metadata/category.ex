defmodule Sanbase.Metric.UIMetadata.Category do
  @moduledoc """
  DEPRECATED: This module is deprecated in favor of Sanbase.Metric.Category.MetricCategory.

  The ui_metadata_categories table is being phased out. Please use the new metric_categories
  table and Sanbase.Metric.Category module for all new code.

  Migration path:
  1. Use Sanbase.Metric.Category.MetricCategory for new categories
  2. Existing data will be migrated gradually
  3. This module will be removed in a future release

  Target deprecation date: Q2 2025
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Metric.UIMetadata.Group

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          display_order: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "ui_metadata_categories" do
    field(:name, :string)
    field(:display_order, :integer)

    has_many(:groups, Group, foreign_key: :category_id)

    timestamps()
  end

  defp log_deprecation_warning(function_name) do
    Logger.warning("""
    DEPRECATED: #{__MODULE__}.#{function_name} is deprecated.
    Please use Sanbase.Metric.Category module instead.
    This function will be removed in a future release.
    """)
  end

  def changeset(%__MODULE__{} = category, attrs) do
    category
    |> cast(attrs, [:name, :display_order])
    |> validate_required([:name, :display_order])
    |> unique_constraint(:name)
  end

  @doc """
  Create a new category.

  DEPRECATED: Use Sanbase.Metric.Category.create_category/1 instead.
  """
  def create(attrs) do
    log_deprecation_warning("create/1")

    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a category.
  """
  def update(%__MODULE__{} = category, attrs) do
    category
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a category.
  """
  def delete(%__MODULE__{} = category) do
    Repo.delete(category)
  end

  @doc """
  Get a category by ID.
  """
  def by_id(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Get a category by name.
  """
  def by_name(name) when is_binary(name) do
    Repo.get_by(__MODULE__, name: name)
  end

  @doc """
  Get all categories.
  """
  def all do
    Repo.all(__MODULE__)
  end

  @doc """
  Get all categories ordered by display_order.
  """
  def all_ordered do
    query =
      from(c in __MODULE__,
        order_by: [asc: c.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Get all categories with their groups.
  """
  def with_groups do
    query =
      from(c in __MODULE__,
        preload: [groups: ^from(g in Group, order_by: [asc: g.name])],
        order_by: [asc: c.display_order]
      )

    Repo.all(query)
  end

  @doc """
  Reorder categories.
  The new_order parameter should be a list of maps with category ID and display_order keys.
  """
  def reorder(new_order) do
    Repo.transaction(fn ->
      Enum.each(new_order, fn %{id: id, display_order: display_order} ->
        case by_id(id) do
          nil ->
            Repo.rollback("Category with ID #{id} not found")

          category ->
            changeset = changeset(category, %{display_order: display_order})

            case Repo.update(changeset) do
              {:ok, _} -> :ok
              {:error, error} -> Repo.rollback(error)
            end
        end
      end)

      :ok
    end)
  end
end
