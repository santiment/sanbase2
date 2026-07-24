defmodule Sanbase.Metric.Tag.MetricTag do
  @moduledoc """
  Schema for metric tags.

  A tag is a controlled-vocabulary label that can be attached to metrics
  (both registry-backed and code-defined ones via `MetricTagMapping`). Tags
  are the mechanism used to expose a curated subset of metrics on bundle
  subscription plans.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Tag.MetricTagMapping

  @type t :: %__MODULE__{
          id: integer(),
          name: String.t(),
          description: String.t() | nil,
          mappings: [MetricTagMapping.t()],
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_tags" do
    field(:name, :string)
    field(:description, :string)

    has_many(:mappings, MetricTagMapping, foreign_key: :tag_id)

    timestamps()
  end

  @doc """
  Creates a changeset for a metric tag.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = tag, attrs) do
    tag
    |> cast(attrs, [:name, :description])
    |> validate_required([:name])
    |> validate_length(:name, min: 1, max: 255)
    |> validate_length(:description, max: 2000)
    |> unique_constraint(:name)
  end

  @doc """
  Creates a new metric tag.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates a metric tag.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = tag, attrs) do
    tag
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes a metric tag. The associated mappings are removed by the
  `on_delete: :delete_all` foreign key.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = tag) do
    Repo.delete(tag)
  end

  @doc """
  Gets a metric tag by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets a metric tag by name.
  """
  @spec get_by_name(String.t()) :: t() | nil
  def get_by_name(name) when is_binary(name) do
    Repo.get_by(__MODULE__, name: name)
  end

  @doc """
  Lists all metric tags ordered by name.
  """
  @spec list_all() :: [t()]
  def list_all() do
    query = from(t in __MODULE__, order_by: [asc: t.name])
    Repo.all(query)
  end
end
