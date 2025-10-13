defmodule Sanbase.Metric.UIMetadata.Group do
  @moduledoc """
  DEPRECATED: This module is deprecated in favor of Sanbase.Metric.Category.MetricGroup.

  The ui_metadata_groups table is being phased out. Please use the new metric_groups
  table and Sanbase.Metric.Category module for all new code.

  Migration path:
  1. Use Sanbase.Metric.Category.MetricGroup for new groups
  2. Existing data will be migrated gradually
  3. This module will be removed in a future release

  Target deprecation date: Q2 2025
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Metric.UIMetadata.Category

  defp log_deprecation_warning(function_name) do
    Logger.warning("""
    DEPRECATED: #{__MODULE__}.#{function_name} is deprecated.
    Please use Sanbase.Metric.Category module instead.
    This function will be removed in a future release.
    """)
  end

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          category_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "ui_metadata_groups" do
    field(:name, :string)

    belongs_to(:category, Category)

    timestamps()
  end

  def changeset(%__MODULE__{} = group, attrs) do
    group
    |> cast(attrs, [:name, :category_id])
    |> validate_required([:name, :category_id])
    |> unique_constraint([:name, :category_id])
    |> foreign_key_constraint(:category_id)
  end

  @doc """
  Create a new group.
  """
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Update a group.
  """
  def update(%__MODULE__{} = group, attrs) do
    group
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Delete a group.
  """
  def delete(%__MODULE__{} = group) do
    Repo.delete(group)
  end

  @doc """
  Get a group by ID.
  """
  def by_id(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Get a group by name and category_id.
  """
  def by_name_and_category(name, category_id) when is_binary(name) and is_integer(category_id) do
    Repo.get_by(__MODULE__, name: name, category_id: category_id)
  end

  @doc """
  Get all groups.
  """
  def all do
    Repo.all(__MODULE__)
  end

  @doc """
  Get all groups for a specific category.
  """
  def by_category(category_id) when is_integer(category_id) do
    query =
      from(g in __MODULE__,
        where: g.category_id == ^category_id,
        order_by: [asc: g.name]
      )

    Repo.all(query)
  end

  @doc """
  Get all groups with their category.
  """
  def with_category do
    query =
      from(g in __MODULE__,
        preload: [:category],
        order_by: [asc: g.name]
      )

    Repo.all(query)
  end

  @doc """
  Create a group if it doesn't exist already.
  """
  def create_if_not_exists(name, category_id) when is_binary(name) and is_integer(category_id) do
    case by_name_and_category(name, category_id) do
      nil ->
        create(%{name: name, category_id: category_id})

      existing ->
        {:ok, existing}
    end
  end
end
