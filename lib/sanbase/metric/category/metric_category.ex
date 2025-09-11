defmodule Sanbase.Metric.Category.MetricCategory do
  @moduledoc """
  Schema for metric categories.

  Categories are the top-level organizational units for metrics, containing
  groups of related metrics.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Category.MetricGroup

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          slug: String.t(),
          short_description: String.t() | nil,
          description: String.t() | nil,
          display_order: integer() | nil,
          groups: [MetricGroup.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_categories" do
    field(:name, :string)
    field(:slug, :string)
    field(:short_description, :string)
    field(:description, :string)
    field(:display_order, :integer)

    has_many(:groups, MetricGroup, foreign_key: :category_id)

    timestamps()
  end

  @doc """
  Creates a changeset for metric category.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = category, attrs) do
    category
    |> cast(attrs, [:name, :slug, :short_description, :description, :display_order])
    |> validate_required([:name, :slug])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:slug, min: 1, max: 255)
    |> validate_format(:slug, ~r/^[a-z0-9_-]+$/,
      message: "must contain only lowercase letters, numbers, hyphens, and underscores"
    )
    |> validate_length(:short_description, max: 500)
    |> validate_length(:description, max: 2000)
    |> validate_number(:display_order, greater_than_or_equal_to: 0)
    |> unique_constraint(:name)
    |> unique_constraint(:slug)
  end

  @doc """
  Creates a new metric category.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a metric category.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = category, attrs) do
    category
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a metric category.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = category) do
    Repo.delete(category)
  end

  @doc """
  Gets a metric category by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets a metric category by slug.
  """
  @spec get_by_slug(String.t()) :: t() | nil
  def get_by_slug(slug) when is_binary(slug) do
    Repo.get_by(__MODULE__, slug: slug)
  end

  @doc """
  Gets a metric category by name.
  """
  @spec get_by_name(String.t()) :: t() | nil
  def get_by_name(name) when is_binary(name) do
    Repo.get_by(__MODULE__, name: name)
  end

  @doc """
  Lists all metric categories ordered by display_order.
  """
  @spec list_ordered() :: [t()]
  def list_ordered do
    query =
      from(c in __MODULE__,
        order_by: [asc: c.display_order, asc: c.name]
      )

    Repo.all(query)
  end

  @doc """
  Lists all metric categories with their groups.
  """
  @spec list_with_groups() :: [t()]
  def list_with_groups do
    query =
      from(c in __MODULE__,
        preload: [groups: ^from(g in MetricGroup, order_by: [asc: g.display_order, asc: g.name])],
        order_by: [asc: c.display_order, asc: c.name]
      )

    Repo.all(query)
  end

  @doc """
  Updates the display order of categories.

  The new_order parameter should be a list of maps with category ID and display_order keys.
  """
  @spec reorder([%{id: integer(), display_order: integer()}]) :: {:ok, :ok} | {:error, any()}
  def reorder(new_order) when is_list(new_order) do
    Repo.transaction(fn ->
      Enum.each(new_order, &update_category_order/1)
      :ok
    end)
  end

  defp update_category_order(%{id: id, display_order: display_order}) do
    case get(id) do
      nil ->
        Repo.rollback("Category with ID #{id} not found")

      category ->
        case update(category, %{display_order: display_order}) do
          {:ok, _} -> :ok
          {:error, error} -> Repo.rollback(error)
        end
    end
  end
end
