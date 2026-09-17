defmodule Sanbase.Metric.VersionAlias do
  @moduledoc ~s"""
  Human-readable names for metric versions.

  Metric versions are opaque strings like "2.1" that encode meaning the API does
  not expose. This table maps a version to a name ("modern_pit:v1"). Each row
  says which metrics it applies to, and the most specific row wins:

    * `global`   - every metric
    * `category` - every metric in a `Sanbase.Metric.Category.MetricCategory`
    * `metric`   - one metric

  Rows of a more specific scope replace less specific rows with the same
  `version_num`. A `NULL` `version_name` removes an inherited alias. `priority`
  only breaks ties between two categories that both name the same version of a
  metric they share; global and metric rows are unique per version already.

  The mapping is applied only at the GraphQL boundary: `to_version_num/2`
  translates a name into the canonical version at the entrance of `getMetric`,
  `to_maps/2` and `to_maps_batch/1` decorate `availableVersions`. Everything in
  between (SQL, cache keys, access control, API-call logging) keeps seeing the
  canonical version.

  The table is a list of aliases, not an allowlist. Versions without a row pass
  through untouched, so a version the data team ships tomorrow works before
  anyone names it.

  See docs/metric-version-aliases.md for the design.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Metric.Category
  alias Sanbase.Metric.Category.MetricCategory

  @type t :: %__MODULE__{}

  @scope_types ["global", "category", "metric"]
  # A name never looks like a canonical version, so the reverse lookup is never
  # ambiguous. The only non-numeric version, "Experimental (Weighted Age)",
  # cannot match this either (spaces, parens).
  @name_regex ~r/^[a-z][a-z0-9_]*(:v\d+(\.\d+)*)?$/
  @cache_key {__MODULE__, :rows}
  @cache_ttl_seconds 300

  schema "metric_version_aliases" do
    field(:scope_type, :string)
    field(:scope_value, :string, default: "")
    belongs_to(:category, MetricCategory)
    field(:version_num, :string)
    field(:version_name, :string)
    field(:description, :string)
    field(:priority, :integer, default: 0)

    timestamps()
  end

  def scope_types(), do: @scope_types

  # Changeset

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = version_alias, attrs) do
    version_alias
    |> cast(attrs, [
      :scope_type,
      :scope_value,
      :category_id,
      :version_num,
      :version_name,
      :description,
      :priority
    ])
    |> update_change(:version_num, &trim/1)
    |> update_change(:scope_value, &trim/1)
    |> update_change(:version_name, &blank_to_nil/1)
    |> validate_required([:scope_type, :version_num, :priority])
    |> validate_inclusion(:scope_type, @scope_types)
    |> validate_format(:version_name, @name_regex,
      message: "must look like modern_pit:v1 - lowercase, digits, underscores, optional :vN.N"
    )
    |> validate_version_num()
    |> validate_scope_shape()
    |> validate_no_name_collision()
    |> foreign_key_constraint(:category_id)
    |> check_constraint(:scope_type,
      name: :metric_version_aliases_scope_shape,
      message: "does not match the scope value and category"
    )
    |> unique_constraint([:scope_type, :scope_value, :version_num],
      name: :metric_version_aliases_scope_version_num_index,
      error_key: :version_num,
      message: "already has an alias in this scope"
    )
    |> unique_constraint([:scope_type, :scope_value, :version_name],
      name: :metric_version_aliases_scope_version_name_index,
      error_key: :version_name,
      message: "is already used by another version in this scope"
    )
    |> unique_constraint([:category_id, :version_num],
      name: :metric_version_aliases_category_version_num_index,
      error_key: :version_num,
      message: "already has an alias in this category"
    )
    |> unique_constraint([:category_id, :version_name],
      name: :metric_version_aliases_category_version_name_index,
      error_key: :version_name,
      message: "is already used by another version in this category"
    )
  end

  # Clearing a field in the edit form arrives as a change to nil.
  defp trim(nil), do: nil
  defp trim(string), do: String.trim(string)

  defp blank_to_nil(string) do
    case trim(string) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp validate_version_num(changeset) do
    num = get_field(changeset, :version_num)

    if is_binary(num) and looks_like_alias?(num),
      do: add_error(changeset, :version_num, "looks like an alias name, not a version"),
      else: changeset
  end

  # The DB check constraint enforces the same shapes; this gives field-level
  # errors in the admin form instead of a constraint error.
  defp validate_scope_shape(changeset) do
    category_id = get_field(changeset, :category_id)

    case get_field(changeset, :scope_type) do
      "global" ->
        changeset
        |> put_change(:scope_value, "")
        |> reject_category(category_id)
        |> reject_priority()

      "category" ->
        changeset |> put_change(:scope_value, "") |> require_category(category_id)

      "metric" ->
        changeset
        |> reject_category(category_id)
        |> reject_priority()
        |> validate_scope_metric()
        |> validate_unique_metric_row()

      _ ->
        changeset
    end
  end

  # Within a global or metric scope there is one row per version_num anyway;
  # priority only breaks ties between categories, so it is refused elsewhere
  # rather than silently ignored.
  defp reject_priority(changeset) do
    if get_field(changeset, :priority) == 0,
      do: changeset,
      else: add_error(changeset, :priority, "only applies to category scope")
  end

  defp reject_category(changeset, nil), do: changeset

  defp reject_category(changeset, _category_id),
    do: add_error(changeset, :category_id, "must be empty unless the scope is category")

  defp require_category(changeset, nil),
    do: add_error(changeset, :category_id, "is required for category scope")

  defp require_category(changeset, _category_id), do: changeset

  defp validate_scope_metric(changeset) do
    case get_field(changeset, :scope_value) do
      empty when empty in [nil, ""] ->
        add_error(changeset, :scope_value, "is required for metric scope")

      metric ->
        case Sanbase.Metric.has_metric?(metric) do
          true -> changeset
          {:error, _} -> add_error(changeset, :scope_value, "is not a known metric")
        end
    end
  end

  # The unique index sees public names; the lookup matches on the internal name
  # (`internal_metric/1`), so two rows typed under different public aliases of one
  # metric would silently collapse. Catch that here - the admin is the only writer.
  defp validate_unique_metric_row(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_unique_metric_row(changeset) do
    metric = get_field(changeset, :scope_value)
    num = get_field(changeset, :version_num)
    id = changeset.data.id

    __MODULE__
    |> where([a], a.scope_type == "metric" and a.version_num == ^num and a.id != ^(id || 0))
    |> Repo.all()
    |> Enum.find(&same_metric?(&1.scope_value, metric))
    |> case do
      nil ->
        changeset

      row ->
        add_error(
          changeset,
          :scope_value,
          "already has an alias for this version as #{row.scope_value}"
        )
    end
  end

  defp same_metric?(name, other), do: internal_metric(name) == internal_metric(other)

  # Admin usability check, not a race guarantee: a name that another row, layered
  # with this one, already gives to a *different* version is rejected here with
  # a useful error. Runtime resolution still detects collisions (`names_index/1`).
  defp validate_no_name_collision(%Ecto.Changeset{valid?: false} = changeset), do: changeset

  defp validate_no_name_collision(changeset) do
    case get_field(changeset, :version_name) do
      nil ->
        changeset

      name ->
        num = get_field(changeset, :version_num)
        id = changeset.data.id

        changeset
        |> layered_rows()
        |> Enum.filter(&(&1.id != id and &1.version_name == name and &1.version_num != num))
        |> Enum.map(& &1.version_num)
        |> Enum.uniq()
        |> Enum.sort()
        |> case do
          [] ->
            changeset

          nums ->
            add_error(
              changeset,
              :version_name,
              "is already the name of version #{Enum.join(nums, ", ")} for metrics this row applies to"
            )
        end
    end
  end

  # Current database rows this row will be merged with, per the precedence rules.
  defp layered_rows(changeset) do
    case get_field(changeset, :scope_type) do
      "global" ->
        Repo.all(__MODULE__)

      "category" ->
        category_id = get_field(changeset, :category_id)

        Repo.all(
          from(a in __MODULE__,
            where: a.scope_type == "global" or a.category_id == ^category_id
          )
        )

      "metric" ->
        metric = get_field(changeset, :scope_value)

        category_ids =
          case Category.Cache.category_ids_for_metric(metric) do
            {:ok, ids} -> ids
            {:error, _} -> []
          end

        Repo.all(
          from(a in __MODULE__,
            where:
              a.scope_type == "global" or a.category_id in ^category_ids or
                a.scope_type == "metric"
          )
        )
        |> Enum.reject(&(&1.scope_type == "metric" and not same_metric?(&1.scope_value, metric)))
    end
  end

  # Lookup

  @doc "Drop the cached rows on this node. Other nodes pick the change up on expiry."
  @spec clear_cache() :: :ok
  def clear_cache() do
    Sanbase.Cache.clear(@cache_key)
    :ok
  end

  @doc ~s"""
  Translate the `version` argument of `getMetric` into the canonical version.

  Input that does not look like an alias (numbers, the Experimental string) passes
  through untouched without consulting the mapping. Alias-looking input must name
  exactly one effective version of the metric - or be one of the metric's real
  versions as ClickHouse reports them (a version called "beta" is not an alias),
  in which case it passes through as well.
  """
  @spec to_version_num(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def to_version_num(metric, input) when is_binary(metric) and is_binary(input) do
    if looks_like_alias?(input), do: resolve_name(metric, input), else: {:ok, input}
  end

  defp resolve_name(metric, name) do
    with {:ok, eff} <- effective(metric) do
      by_name = names_index(eff)

      case Map.get(by_name, name, []) do
        [num] ->
          {:ok, num}

        [] ->
          if known_version?(metric, name),
            do: {:ok, name},
            else: {:error, unknown_name_error(metric, name, by_name)}

        nums ->
          {:error, ambiguous_name_error(metric, name, Enum.sort(nums))}
      end
    else
      {:error, reason} ->
        Logger.error(
          "Cannot resolve metric version name #{inspect(name)} for #{metric}: #{inspect(reason)}"
        )

        {:error,
         "Version names cannot be resolved at the moment. Use the numeric version instead."}
    end
  end

  @doc ~s"""
  `Sanbase.Metric.available_versions/1` behind a short cache. Shared by the
  `getMetric` middleware (to let a real version through) and the
  `availableVersions` resolver, so both see the same list.
  """
  @spec cached_available_versions(String.t()) :: {:ok, [String.t()]} | {:error, String.t()}
  def cached_available_versions(metric) when is_binary(metric) do
    Sanbase.Cache.get_or_store({{__MODULE__, :available_versions, metric}, 120}, fn ->
      Sanbase.Metric.available_versions(metric)
    end)
  end

  defp known_version?(metric, version) do
    case cached_available_versions(metric) do
      {:ok, versions} -> version in versions
      {:error, _} -> false
    end
  end

  @doc ~s"""
  Decorate one metric's versions for `availableVersions`. See `to_maps_batch/1`.
  """
  @spec to_maps(String.t(), [String.t()]) :: [map()]
  def to_maps(metric, versions) when is_binary(metric) and is_list(versions) do
    %{metric => versions} |> to_maps_batch() |> Map.fetch!(metric)
  end

  @doc ~s"""
  Decorate the versions of many metrics at once: `%{metric => [version]}` in,
  `%{metric => [map]}` out. Both caches are read once per call, so this is the
  form for the access-restrictions dataloader, which decorates every metric of
  a request together.

  `version_name` is never nil: it falls back to the version itself when no row
  applies or when the name is given to several versions of that metric (such a
  name is not accepted as input, so it is not advertised).
  """
  @spec to_maps_batch(%{String.t() => [String.t()]}) :: %{String.t() => [map()]}
  def to_maps_batch(versions_by_metric) when is_map(versions_by_metric) do
    case caches() do
      {:ok, caches} ->
        Map.new(versions_by_metric, fn {metric, versions} ->
          eff = effective(metric, caches)
          unambiguous = eff |> names_index() |> unambiguous_names() |> MapSet.new()

          {metric, Enum.map(versions, &to_map(&1, Map.get(eff, &1), unambiguous))}
        end)

      {:error, reason} ->
        Logger.error("Cannot load metric version aliases: #{inspect(reason)}")

        Map.new(versions_by_metric, fn {metric, versions} ->
          {metric, Enum.map(versions, &to_map(&1, nil, MapSet.new()))}
        end)
    end
  end

  defp to_map(version, row, unambiguous) do
    name = row && row.version_name
    version_name = if name && MapSet.member?(unambiguous, name), do: name, else: version

    %{
      version: version,
      version_num: version,
      version_name: version_name,
      description: row && row.description
    }
  end

  defp looks_like_alias?(input), do: Regex.match?(@name_regex, input)

  # Both caches, each read once. `{:error, _}` (not cached) when either cannot be
  # loaded, so a caller never silently falls back to a partial mapping.
  defp caches() do
    with {:ok, rows} <- rows(),
         {:ok, categories} <- Category.Cache.metric_to_category_ids_map() do
      {:ok, %{rows: rows, categories: categories}}
    end
  end

  defp effective(metric) do
    with {:ok, caches} <- caches(), do: {:ok, effective(metric, caches)}
  end

  # The effective `version_num => row` mapping for one metric: global rows, then
  # rows of every category the metric is in, then metric rows. Higher layers
  # replace lower ones by version_num.
  defp effective(metric, %{rows: rows, categories: categories}) do
    category_layer =
      categories
      |> Map.get(metric, [])
      |> Enum.flat_map(&Map.values(Map.get(rows.category, &1, %{})))
      |> resolve_conflicts()

    rows.global
    |> Map.merge(category_layer)
    |> Map.merge(Map.get(rows.metric, internal_metric(metric), %{}))
  end

  # `version_name => [version_num]`. Keeps every match so a name shared by two
  # versions is detected instead of silently overwritten.
  defp names_index(effective) do
    effective
    |> Map.values()
    |> Enum.reject(&is_nil(&1.version_name))
    |> Enum.group_by(& &1.version_name, & &1.version_num)
  end

  defp unambiguous_names(by_name) do
    for {name, [_single]} <- by_name, do: name
  end

  # One row per version_num: higher priority wins, then the lower category id,
  # then the lower row id - deterministic and immune to category renames.
  defp resolve_conflicts(rows) do
    rows
    |> Enum.group_by(& &1.version_num)
    |> Map.new(fn {num, rows} ->
      {num, Enum.min_by(rows, &{-&1.priority, &1.category_id || 0, &1.id})}
    end)
  end

  defp rows() do
    Sanbase.Cache.get_or_store({@cache_key, @cache_ttl_seconds}, fn -> load_rows() end)
  end

  # Rows grouped by scope and already reduced to one row per version_num, so a
  # request only merges small maps.
  defp load_rows() do
    grouped = __MODULE__ |> Repo.all() |> Enum.group_by(& &1.scope_type)

    {:ok,
     %{
       global: grouped |> Map.get("global", []) |> resolve_conflicts(),
       category:
         grouped
         |> Map.get("category", [])
         |> Enum.group_by(& &1.category_id)
         |> Map.new(fn {id, rows} -> {id, resolve_conflicts(rows)} end),
       metric:
         grouped
         |> Map.get("metric", [])
         |> Enum.group_by(&internal_metric(&1.scope_value))
         |> Map.new(fn {metric, rows} -> {metric, resolve_conflicts(rows)} end)
     }}
  rescue
    e ->
      Logger.error("Failed to load metric version aliases: #{Exception.message(e)}")
      {:error, :version_aliases_unavailable}
  end

  # A metric can be requested under several public names. Metric-scoped rows are
  # matched on the internal name so the caller's choice of alias does not matter.
  defp internal_metric(metric) do
    Map.get(Sanbase.Clickhouse.MetricAdapter.Registry.name_to_metric_map(), metric, metric)
  end

  defp unknown_name_error(metric, name, by_name) do
    known = by_name |> unambiguous_names() |> Enum.sort() |> Enum.join(", ")

    "#{inspect(name)} is not a version name of #{metric}. Known names: #{known}. " <>
      "Numeric versions are always accepted."
  end

  defp ambiguous_name_error(metric, name, nums) do
    "#{inspect(name)} names more than one version of #{metric} (#{Enum.join(nums, ", ")}). " <>
      "Use the numeric version instead."
  end
end
