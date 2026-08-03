defmodule Sanbase.Billing.Plan.Bundle.PackageSnapshot do
  @moduledoc ~s"""
  A published, frozen answer to "which metrics does each package contain?".

  ## Why this is frozen rather than read live

  Metric categorization is edited continuously by admins in the categorization
  screen. Reading category membership live at access-check time would mean that
  moving one metric between categories grants or revokes something a customer
  paid for - a billing change made through a UI that does not look like one, with
  no record of who made it or when.

  So the rules in `Sanbase.Billing.Plan.Bundle.Package` are materialized into a
  numbered snapshot, and each bundle subscription records the version it was
  resolved against (`package_snapshot_version` on the entitlement). Two customers
  who bought Market months apart can therefore hold different metric lists, which
  is the intended behavior: a customer keeps what they paid for until something
  deliberately re-resolves them.

  The cost is that publishing is a deliberate act. `pending_changes/0` shows what
  a publish would change, so it can be reviewed first.

  ## What is left out

  Deprecated and hidden metrics are excluded (§6.1). Queries and signals are not
  here at all - every bundle gets all of them, so there is nothing to snapshot
  (§6.4).
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Billing.Plan.Bundle.Package
  alias Sanbase.Metric.Category.MetricCategory
  alias Sanbase.Metric.Category.MetricCategoryMapping
  alias Sanbase.Metric.Registry
  alias Sanbase.Repo

  require Logger

  @type contents :: %{String.t() => [String.t()]}

  @type t :: %__MODULE__{
          id: integer(),
          version: integer(),
          contents: contents(),
          notes: String.t() | nil,
          published_at: DateTime.t()
        }

  schema "bundle_package_snapshots" do
    field(:version, :integer)
    field(:contents, :map)
    field(:notes, :string)
    field(:published_at, :utc_datetime)

    timestamps()
  end

  @doc false
  def changeset(%__MODULE__{} = snapshot, attrs) do
    snapshot
    |> cast(attrs, [:version, :contents, :notes, :published_at])
    |> validate_required([:version, :contents, :published_at])
    |> validate_change(:contents, &validate_contents/2)
    |> unique_constraint(:version)
  end

  @doc ~s"""
  The most recently published snapshot, or `nil` if none has been published.
  """
  @spec latest() :: t() | nil
  def latest do
    from(s in __MODULE__, order_by: [desc: s.version], limit: 1)
    |> Repo.one()
  end

  @doc ~s"""
  The snapshot with this version number.
  """
  @spec by_version(integer()) :: t() | nil
  def by_version(version) when is_integer(version),
    do: Repo.get_by(__MODULE__, version: version)

  @doc ~s"""
  Work out what each package contains from the current categorization, without
  storing anything.

  Fails rather than returning a partial answer if any package's category is
  missing. An empty package would look like a working configuration while
  silently selling nothing, so a missing category has to be loud.
  """
  @spec materialize() :: {:ok, contents()} | {:error, String.t()}
  def materialize do
    categories = Repo.all(MetricCategory) |> Map.new(&{&1.name, &1})

    case Enum.reject(Package.all(), &Map.has_key?(categories, &1.category)) do
      [] ->
        {:ok, build_contents(categories)}

      missing ->
        {:error, missing_categories_message(missing, categories)}
    end
  end

  @doc ~s"""
  Publish the current categorization as the next snapshot version.

  Options:

    * `:notes` - free text recorded with the snapshot, e.g. why it was published.
  """
  @spec publish(keyword()) :: {:ok, t()} | {:error, String.t() | Ecto.Changeset.t()}
  def publish(opts \\ []) do
    with {:ok, contents} <- materialize() do
      next_version =
        case latest() do
          nil -> 1
          %__MODULE__{version: version} -> version + 1
        end

      %__MODULE__{}
      |> changeset(%{
        version: next_version,
        contents: contents,
        notes: Keyword.get(opts, :notes),
        published_at: DateTime.utc_now() |> DateTime.truncate(:second)
      })
      |> Repo.insert()
    end
  end

  @doc ~s"""
  What publishing right now would change, per package.

  Only packages that would change are listed. An empty map means the latest
  snapshot already matches the current categorization. This is what an admin
  should see before publishing - and what makes the "categorization edits are
  billing changes" problem visible instead of implicit.
  """
  @spec pending_changes() ::
          {:ok, %{String.t() => %{added: [String.t()], removed: [String.t()]}}}
          | {:error, String.t()}
  def pending_changes do
    with {:ok, live} <- materialize() do
      published =
        case latest() do
          nil -> %{}
          %__MODULE__{contents: contents} -> contents
        end

      {:ok, diff(published, live)}
    end
  end

  @doc ~s"""
  Per-package difference between two `contents` maps.
  """
  @spec diff(contents(), contents()) ::
          %{String.t() => %{added: [String.t()], removed: [String.t()]}}
  def diff(before, later) do
    Package.slugs()
    |> Enum.reduce(%{}, fn slug, acc ->
      old = MapSet.new(Map.get(before, slug, []))
      new = MapSet.new(Map.get(later, slug, []))

      added = MapSet.difference(new, old) |> Enum.sort()
      removed = MapSet.difference(old, new) |> Enum.sort()

      case {added, removed} do
        {[], []} -> acc
        _ -> Map.put(acc, slug, %{added: added, removed: removed})
      end
    end)
  end

  @doc ~s"""
  The metrics granted by owning all of the given packages - the union of their
  lists.

  Unknown slugs contribute nothing rather than raising: a snapshot published
  before a package existed genuinely has no list for it, and an entitlement is
  re-resolved against a newer snapshot rather than repaired here.
  """
  @spec metrics_for(t() | contents(), [String.t()]) :: [String.t()]
  def metrics_for(%__MODULE__{contents: contents}, slugs), do: metrics_for(contents, slugs)

  def metrics_for(contents, slugs) when is_map(contents) and is_list(slugs) do
    slugs
    |> Enum.flat_map(&Map.get(contents, &1, []))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # Private

  defp build_contents(categories) do
    Map.new(Package.all(), fn package ->
      category = Map.fetch!(categories, package.category)

      {package.slug, metrics_in_category(category.id)}
    end)
  end

  defp metrics_in_category(category_id) do
    mappings = MetricCategoryMapping.get_by_category_id(category_id)

    (registry_metrics(mappings) ++ code_metrics(mappings))
    |> Enum.uniq()
    |> Enum.sort()
  end

  # A registry row can be a template standing for many concrete metrics
  # (`social_volume_{{source}}`), and access checks are made against the
  # concrete names, so the templates have to be expanded here.
  defp registry_metrics(mappings) do
    {resolved, failed} =
      mappings
      |> Enum.map(& &1.metric_registry)
      |> Enum.filter(&sellable?/1)
      |> Registry.resolve_safe()

    if failed != [] do
      Logger.error("""
      #{length(failed)} metric registry rows failed to resolve while building a \
      bundle package snapshot and were left out: \
      #{failed |> Enum.map(& &1.metric) |> Enum.join(", ")}
      """)
    end

    Enum.map(resolved, & &1.metric)
  end

  # Metrics served by adapter modules rather than the registry. Nothing to
  # expand and no deprecation flags to read - the mapping carries the name.
  defp code_metrics(mappings) do
    for %{metric_registry_id: nil, metric: metric} <- mappings,
        is_binary(metric),
        do: metric
  end

  defp sellable?(%Registry{is_deprecated: true}), do: false
  defp sellable?(%Registry{is_hidden: true}), do: false
  defp sellable?(%Registry{}), do: true
  defp sellable?(_), do: false

  defp missing_categories_message(missing, categories) do
    """
    Cannot build a bundle package snapshot: #{length(missing)} package(s) name a \
    metric category that does not exist.

    Missing: #{missing |> Enum.map(&"#{&1.slug} -> #{inspect(&1.category)}") |> Enum.join(", ")}

    Existing categories: #{categories |> Map.keys() |> Enum.sort() |> Enum.map_join(", ", &inspect/1)}

    Either the category was renamed, or the environment has not been categorized \
    yet. Fix the name in Sanbase.Billing.Plan.Bundle.Package rather than \
    publishing a snapshot with an empty package.
    """
  end

  defp validate_contents(:contents, contents) when is_map(contents) do
    missing = Enum.reject(Package.slugs(), &Map.has_key?(contents, &1))

    unknown = Map.keys(contents) -- Package.slugs()

    cond do
      missing != [] ->
        [contents: "is missing an entry for #{Enum.join(missing, ", ")}"]

      unknown != [] ->
        [contents: "has entries for unknown packages: #{Enum.join(unknown, ", ")}"]

      not Enum.all?(Map.values(contents), &list_of_strings?/1) ->
        [contents: "every package must map to a list of metric names"]

      true ->
        []
    end
  end

  defp validate_contents(:contents, _), do: [contents: "must be a map"]

  defp list_of_strings?(value), do: is_list(value) and Enum.all?(value, &is_binary/1)
end
