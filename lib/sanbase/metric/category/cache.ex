defmodule Sanbase.Metric.Category.Cache do
  @moduledoc ~s"""
  Cached `concrete metric name => [category id]` lookup, built from
  `metric_category_mappings` with `Sanbase.Metric.Registry.mapping_names_resolver/1`
  (registry templates and public aliases expanded, module-backed rows as they are).

  A database failure returns `{:error, reason}` and is not cached: a caller
  such as `Sanbase.Metric.VersionAlias` must not mistake "could not load" for
  "belongs to no category", or it would silently drop category overrides.
  """

  import Ecto.Query

  require Logger

  alias Sanbase.Metric.Registry
  alias Sanbase.Metric.Category.MetricCategoryMapping

  @cache_key {__MODULE__, :metric_to_category_ids}
  @cache_ttl_seconds 300

  @doc "The ids of the categories the metric is in. `{:ok, []}` when it is in none."
  @spec category_ids_for_metric(String.t()) :: {:ok, [integer()]} | {:error, term()}
  def category_ids_for_metric(metric) when is_binary(metric) do
    with {:ok, map} <- metric_to_category_ids_map() do
      {:ok, Map.get(map, metric, [])}
    end
  end

  @doc "The whole map, for callers that look up many metrics at once."
  @spec metric_to_category_ids_map() :: {:ok, %{String.t() => [integer()]}} | {:error, term()}
  def metric_to_category_ids_map() do
    Sanbase.Cache.get_or_store({@cache_key, @cache_ttl_seconds}, fn -> compute() end)
  end

  @doc "Drop the cached map on this node. Other nodes pick the change up on expiry."
  @spec clear() :: :ok
  def clear() do
    Sanbase.Cache.clear(@cache_key)
    :ok
  end

  @doc ~s"""
  Pipe a `Repo` write result through this wherever membership can change:
  mapping writes, and group/category deletes (their mappings go by cascade).
  """
  @spec clear_on_success(result) :: result when result: {:ok, term()} | {:error, term()}
  def clear_on_success({:ok, _} = result) do
    clear()
    result
  end

  def clear_on_success(other), do: other

  defp compute() do
    # Only the registry row is needed to expand a mapping to metric names.
    mappings =
      Sanbase.Repo.all(from(m in MetricCategoryMapping, preload: [:metric_registry]))

    names_for = Registry.mapping_names_resolver(mappings)

    map =
      mappings
      |> Enum.flat_map(fn mapping ->
        for name <- names_for.(mapping), do: {name, mapping.category_id}
      end)
      |> Enum.group_by(fn {name, _id} -> name end, fn {_name, id} -> id end)
      |> Map.new(fn {name, ids} -> {name, Enum.uniq(ids)} end)

    {:ok, map}
  rescue
    e ->
      Logger.error(
        "[#{inspect(__MODULE__)}] Failed to compute metric to categories map: #{Exception.message(e)}"
      )

      {:error, :category_mappings_unavailable}
  end
end
