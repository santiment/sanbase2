defmodule Sanbase.Metric.UIMetadata do
  @moduledoc """
  Module for handling UI metadata for metrics, categories, and groups.
  """
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Repo

  @type t :: %__MODULE__{
          id: integer(),
          ui_human_readable_name: String.t() | nil,
          ui_key: String.t() | nil,
          chart_style: String.t() | nil,
          unit: String.t() | nil,
          args: map() | nil,
          show_on_sanbase: boolean(),
          metric_category_mapping_id: integer(),
          metric_category_mapping: MetricCategoryMapping.t() | nil,
          inserted_at: DateTime.t(),
          updated_at: DateTime.t()
        }

  schema "metric_ui_metadata" do
    field(:ui_human_readable_name, :string)
    field(:ui_key, :string)
    field(:chart_style, :string)
    field(:unit, :string)
    field(:args, :map)
    field(:show_on_sanbase, :boolean, default: true)

    belongs_to(:metric_category_mapping, MetricCategoryMapping)

    timestamps()
  end

  @doc """
  Creates a changeset for UI metadata.
  """
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = ui_metadata, attrs) do
    ui_metadata
    |> cast(attrs, [
      :ui_human_readable_name,
      :ui_key,
      :chart_style,
      :unit,
      :args,
      :show_on_sanbase,
      :metric_category_mapping_id
    ])
    |> validate_required([:metric_category_mapping_id])
    |> validate_json_args()
    |> foreign_key_constraint(:metric_category_mapping_id)
    |> unique_constraint(:metric_category_mapping_id)
  end

  @doc """
  Creates new UI metadata.
  """
  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates UI metadata.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = ui_metadata, attrs) do
    ui_metadata
    |> changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes UI metadata.
  """
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = ui_metadata) do
    Repo.delete(ui_metadata)
  end

  @doc """
  Gets UI metadata by ID.
  """
  @spec get(integer()) :: t() | nil
  def get(id) when is_integer(id) do
    Repo.get(__MODULE__, id)
  end

  @doc """
  Gets UI metadata by metric category mapping ID.
  """
  @spec get_by_mapping_id(integer()) :: t() | nil
  def get_by_mapping_id(mapping_id) when is_integer(mapping_id) do
    query =
      from(u in __MODULE__,
        where: u.metric_category_mapping_id == ^mapping_id,
        preload: [:metric_category_mapping]
      )

    Repo.one(query)
  end

  @doc """
  Lists all UI metadata with preloaded mappings.
  """
  @spec list_all() :: [t()]
  def list_all do
    query =
      from(u in __MODULE__,
        preload: [:metric_category_mapping]
      )

    Repo.all(query)
  end

  defp validate_json_args(changeset) do
    case get_change(changeset, :args) do
      nil ->
        changeset

      args when is_map(args) ->
        changeset

      _ ->
        add_error(changeset, :args, "must be a valid map")
    end
  end
end
