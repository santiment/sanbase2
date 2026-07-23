defmodule Sanbase.Metric.Tag.MetricTagMapping do
  @moduledoc """
  Schema mapping metrics to tags.

  A mapping references a metric either by `metric_registry_id` (registry-backed
  metrics) or by a `module`/`metric` string pair (code-defined metrics that live
  outside the registry, e.g. `price_usd`, github/social metrics). A DB check
  constraint enforces that exactly one of the two identifiers is set.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo
  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Tag.MetricTag

  @type t :: %__MODULE__{
          id: integer(),
          metric_registry_id: integer() | nil,
          metric_registry: Registry.t() | nil,
          module: String.t() | nil,
          metric: String.t() | nil,
          tag: MetricTag.t(),
          tag_id: integer(),
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_tag_mappings" do
    # Either module/metric is set and metric_registry is nil, or vice versa.
    # There is a DB constraint check for that as well.
    field(:module, :string)
    field(:metric, :string)

    belongs_to(:metric_registry, Registry, foreign_key: :metric_registry_id)
    belongs_to(:tag, MetricTag, foreign_key: :tag_id)

    timestamps()
  end

  @doc """
  Creates a changeset for a metric tag mapping.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = mapping, attrs) do
    mapping
    |> cast(attrs, [:metric_registry_id, :module, :metric, :tag_id])
    |> Sanbase.Metric.MetricReference.validate_metric_reference()
    |> validate_length(:module, max: 255)
    |> validate_length(:metric, max: 255)
    |> validate_required([:tag_id])
    |> foreign_key_constraint(:tag_id)
    |> foreign_key_constraint(:metric_registry_id)
    # The unique constraints don't apply when the field is nil.
    # Either metric_registry_id or module/metric is set.
    |> unique_constraint([:metric_registry_id, :tag_id],
      name: :metric_tag_mappings_metric_registry_id_tag_id_index
    )
    |> unique_constraint([:module, :metric, :tag_id],
      name: :metric_tag_mappings_module_metric_tag_id_index
    )
  end

  @doc """
  Creates a new metric tag mapping.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Deletes a metric tag mapping.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = mapping) do
    Repo.delete(mapping)
  end

  @doc """
  Gets a metric tag mapping by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    query =
      from(m in __MODULE__,
        where: m.id == ^id,
        preload: [:tag, :metric_registry]
      )

    Repo.one(query)
  end

  @doc """
  Gets all mappings for a given tag id.
  """
  @spec get_by_tag_id(integer()) :: [t()]
  def get_by_tag_id(tag_id) when is_integer(tag_id) do
    query =
      from(m in __MODULE__,
        where: m.tag_id == ^tag_id,
        preload: [:tag, :metric_registry],
        order_by: [asc: m.id]
      )

    Repo.all(query)
  end

  @doc """
  Lists all metric tag mappings with their related data.
  """
  @spec list_all() :: [t()]
  def list_all() do
    query =
      from(m in __MODULE__,
        preload: [:tag, :metric_registry]
      )

    Repo.all(query)
  end

  @doc """
  Returns a map of tag id to the number of mappings carrying that tag.
  """
  @spec count_per_tag() :: %{integer() => non_neg_integer()}
  def count_per_tag() do
    from(m in __MODULE__, group_by: m.tag_id, select: {m.tag_id, count(m.id)})
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  Creates a mapping by metric registry id.
  """
  @spec create_by_metric_registry_id(integer(), integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_by_metric_registry_id(metric_registry_id, tag_id)
      when is_integer(metric_registry_id) and is_integer(tag_id) do
    create(%{metric_registry_id: metric_registry_id, tag_id: tag_id})
  end

  @doc """
  Creates a mapping by module and metric.
  """
  @spec create_by_module_and_metric(String.t(), String.t(), integer()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create_by_module_and_metric(module, metric, tag_id)
      when is_binary(module) and is_binary(metric) and is_integer(tag_id) do
    create(%{module: module, metric: metric, tag_id: tag_id})
  end
end
