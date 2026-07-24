defmodule Sanbase.Metric.Tag do
  @moduledoc """
  Context module for metric tags.

  Tags are a controlled-vocabulary labeling mechanism for metrics. A tag can be
  attached to registry-backed metrics as well as to code-defined metrics that
  live outside the registry. The primary consumer is the bundle subscription
  plans, which expose only the metrics carrying a given tag.

  This module is the public API. Persistent-term-cached tag <-> metric name
  resolution lives in `Sanbase.Metric.Tag.Cache`.
  """

  alias Sanbase.Repo
  alias Sanbase.Metric.Tag.MetricTag
  alias Sanbase.Metric.Tag.MetricTagMapping
  alias Sanbase.Metric.Tag.Cache
  alias Sanbase.Metric.Tag.EventEmitter

  @vocabulary_tags [
    %{name: "basic", description: "Metrics exposed on the Basic bundle plan"},
    %{name: "development_data", description: "Development activity metrics"},
    %{name: "market_data", description: "Price and market metrics"},
    %{name: "social_data", description: "Social volume and sentiment metrics"},
    %{name: "onchain_data", description: "Onchain and blockchain metrics"}
  ]

  # Tag operations

  @doc """
  Creates a new metric tag.
  """
  @spec create_tag(map()) :: {:ok, MetricTag.t()} | {:error, Ecto.Changeset.t()}
  def create_tag(attrs) do
    MetricTag.create(attrs) |> emit_on_change()
  end

  @doc """
  Updates a metric tag.
  """
  @spec update_tag(MetricTag.t(), map()) :: {:ok, MetricTag.t()} | {:error, Ecto.Changeset.t()}
  def update_tag(%MetricTag{} = tag, attrs) do
    MetricTag.update(tag, attrs) |> emit_on_change()
  end

  @doc """
  Deletes a metric tag (and, via the FK, its mappings).
  """
  @spec delete_tag(MetricTag.t()) :: {:ok, MetricTag.t()} | {:error, Ecto.Changeset.t()}
  def delete_tag(%MetricTag{} = tag) do
    MetricTag.delete(tag) |> emit_on_change()
  end

  @doc """
  Gets a metric tag by ID.
  """
  @spec get_tag(integer()) :: {:ok, MetricTag.t()} | {:error, String.t()}
  def get_tag(id) do
    case MetricTag.get(id) do
      %MetricTag{} = tag -> {:ok, tag}
      nil -> {:error, "Metric tag with id #{id} does not exist"}
    end
  end

  @doc """
  Gets a metric tag by name.
  """
  @spec get_tag_by_name(String.t()) :: MetricTag.t() | nil
  def get_tag_by_name(name), do: MetricTag.get_by_name(name)

  @doc """
  Lists all metric tags ordered by name.
  """
  @spec list_tags() :: [MetricTag.t()]
  def list_tags(), do: MetricTag.list_all()

  @doc """
  Idempotently inserts the seed vocabulary tags.

  Production databases get these from the migration that created the
  `metric_tags` table. Databases created by loading `structure.sql` (like the
  test database) contain no data, so the seeds must be applied separately.
  """
  @spec seed_vocabulary_tags() :: :ok
  def seed_vocabulary_tags() do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      Enum.map(@vocabulary_tags, &Map.merge(&1, %{inserted_at: now, updated_at: now}))

    Repo.insert_all(MetricTag, entries, on_conflict: :nothing, conflict_target: :name)

    :ok
  end

  # Mapping operations

  @doc """
  Gets a metric tag mapping by ID.
  """
  @spec get_mapping(integer()) :: {:ok, MetricTagMapping.t()} | {:error, String.t()}
  def get_mapping(id) do
    case MetricTagMapping.get(id) do
      %MetricTagMapping{} = mapping -> {:ok, mapping}
      nil -> {:error, "Metric tag mapping with id #{id} does not exist"}
    end
  end

  @doc """
  Creates a new metric tag mapping.
  """
  @spec create_mapping(map()) :: {:ok, MetricTagMapping.t()} | {:error, Ecto.Changeset.t()}
  def create_mapping(attrs) do
    MetricTagMapping.create(attrs) |> emit_on_change()
  end

  @doc """
  Deletes a metric tag mapping.
  """
  @spec delete_mapping(MetricTagMapping.t()) ::
          {:ok, MetricTagMapping.t()} | {:error, Ecto.Changeset.t()}
  def delete_mapping(%MetricTagMapping{} = mapping) do
    MetricTagMapping.delete(mapping) |> emit_on_change()
  end

  @doc """
  Lists all mappings for a given tag id.
  """
  @spec list_mappings_by_tag(integer()) :: [MetricTagMapping.t()]
  def list_mappings_by_tag(tag_id), do: MetricTagMapping.get_by_tag_id(tag_id)

  @doc """
  Lists all metric tag mappings.
  """
  @spec list_all_mappings() :: [MetricTagMapping.t()]
  def list_all_mappings(), do: MetricTagMapping.list_all()

  @doc """
  Returns a map of tag id to the number of mappings carrying that tag.
  """
  @spec count_mappings_per_tag() :: %{integer() => non_neg_integer()}
  def count_mappings_per_tag(), do: MetricTagMapping.count_per_tag()

  # Access / resolution (delegated to the persistent-term cache)

  @doc """
  Returns the `MapSet` of concrete metric names carrying the given tag.
  """
  @spec metrics_for_tag(String.t()) :: MapSet.t()
  def metrics_for_tag(tag_name), do: Cache.metrics_for_tag(tag_name)

  @doc """
  Returns the `MapSet` union of concrete metric names carrying any of the given tags.
  """
  @spec metrics_for_tags([String.t()]) :: MapSet.t()
  def metrics_for_tags(tag_names), do: Cache.metrics_for_tags(tag_names)

  @doc """
  Returns the list of tag names attached to the given metric.
  """
  @spec tags_for_metric(String.t()) :: [String.t()]
  def tags_for_metric(metric), do: Cache.tags_for_metric(metric)

  @doc """
  Refreshes the persistent-term tag -> metric caches.

  Callers reacting to tag or registry changes must also refresh the caches
  that are derived from tags — the custom/bundle plan caches
  (`Sanbase.Billing.Plan.CustomPlan.Loader`) — see
  `Sanbase.Metric.Registry.refresh_stored_terms/0` and
  `Sanbase.EventBus.MetricRegistrySubscriber.on_metric_tag_change/0`.
  """
  @spec refresh_stored_terms() :: true
  def refresh_stored_terms() do
    Cache.refresh_stored_terms()
  end

  # Private

  defp emit_on_change({:ok, _} = result) do
    EventEmitter.emit_event(result, :metric_tag_change, %{})
    result
  end

  defp emit_on_change({:error, _} = result), do: result
end
