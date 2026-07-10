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

  alias Sanbase.Metric.Tag.MetricTag
  alias Sanbase.Metric.Tag.MetricTagMapping
  alias Sanbase.Metric.Tag.Cache
  alias Sanbase.Metric.Registry.EventEmitter

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
  Refreshes the persistent-term caches that depend on tags. Also refreshes the
  custom/bundle plan caches, since a bundle plan's resolved metric set depends
  on the tag -> metric mapping.
  """
  @spec refresh_stored_terms() :: true
  def refresh_stored_terms() do
    true = Cache.refresh_stored_terms()
    # Side-effecting: repopulates the bundle/custom-plan persistent_term caches,
    # whose resolved metric sets depend on the tag -> metric mapping. Returns a
    # list, not a status; it signals failure by raising.
    Sanbase.Billing.Plan.CustomPlan.Loader.put_plans_in_persistent_term()
    true
  end

  # Private

  defp emit_on_change({:ok, _} = result) do
    EventEmitter.emit_event(result, :metric_tag_change, %{})
    result
  end

  defp emit_on_change({:error, _} = result), do: result
end
