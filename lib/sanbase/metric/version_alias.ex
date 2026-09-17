defmodule Sanbase.Metric.VersionAlias do
  @moduledoc ~s"""
  Human-readable names for metric versions.

  Metric versions are opaque strings like "2.1" that encode meaning the API does
  not expose. This table maps a version to a name ("modern_pit:v1"), the same
  for every metric.

  The mapping is applied only at the GraphQL boundary: `to_version_num/2`
  translates a name into the canonical version at the entrance of `getMetric`,
  `to_maps/1` decorates `availableVersions`. Everything in between (SQL, cache
  keys, access control, API-call logging) keeps seeing the canonical version.

  The table is a list of aliases, not an allowlist. Versions without a row pass
  through untouched, so a version the data team ships tomorrow works before
  anyone names it.

  See docs/metric-version-aliases.md for the design and for the per-category /
  per-metric scoping that was deliberately left out.
  """

  use Ecto.Schema
  import Ecto.Changeset

  require Logger

  alias Sanbase.Repo

  @type t :: %__MODULE__{}

  # A name never looks like a canonical version, so the reverse lookup is never
  # ambiguous. The only non-numeric version, "Experimental (Weighted Age)",
  # cannot match this either (spaces, parens).
  @name_regex ~r/^[a-z][a-z0-9_]*(:v\d+(\.\d+)*)?$/
  @cache_key {__MODULE__, :aliases}
  @cache_ttl_seconds 300

  schema "metric_version_aliases" do
    field(:version_num, :string)
    field(:version_name, :string)
    field(:description, :string)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = version_alias, attrs) do
    version_alias
    |> cast(attrs, [:version_num, :version_name, :description])
    |> update_change(:version_num, &trim/1)
    |> update_change(:version_name, &trim/1)
    |> validate_required([:version_num, :version_name])
    |> validate_format(:version_name, @name_regex,
      message: "must look like modern_pit:v1 - lowercase, digits, underscores, optional :vN.N"
    )
    |> validate_version_num()
    |> unique_constraint(:version_num, message: "already has a name")
    |> unique_constraint(:version_name, message: "is already the name of another version")
  end

  # Clearing a field in the edit form arrives as a change to nil.
  defp trim(nil), do: nil
  defp trim(string), do: String.trim(string)

  defp validate_version_num(changeset) do
    num = get_field(changeset, :version_num)

    if is_binary(num) and looks_like_alias?(num),
      do: add_error(changeset, :version_num, "looks like an alias name, not a version"),
      else: changeset
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
  through untouched without consulting the mapping. Alias-looking input must be a
  known name - or one of the metric's real versions as ClickHouse reports them (a
  version called "beta" is not an alias), in which case it passes through as well.
  """
  @spec to_version_num(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def to_version_num(metric, input) when is_binary(metric) and is_binary(input) do
    if looks_like_alias?(input), do: resolve_name(metric, input), else: {:ok, input}
  end

  defp resolve_name(metric, name) do
    case aliases() do
      {:ok, %{by_name: by_name}} ->
        cond do
          Map.has_key?(by_name, name) -> {:ok, by_name[name]}
          known_version?(metric, name) -> {:ok, name}
          true -> {:error, unknown_name_error(metric, name, by_name)}
        end

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
  Decorate versions for `availableVersions`. `version_name` is never nil: it
  falls back to the version itself when no row exists.
  """
  @spec to_maps([String.t()]) :: [map()]
  def to_maps(versions) when is_list(versions) do
    by_num =
      case aliases() do
        {:ok, %{by_num: by_num}} ->
          by_num

        {:error, reason} ->
          Logger.error("Cannot load metric version aliases: #{inspect(reason)}")
          %{}
      end

    Enum.map(versions, fn version ->
      row = Map.get(by_num, version)

      %{
        version: version,
        version_num: version,
        version_name: (row && row.version_name) || version,
        description: row && row.description
      }
    end)
  end

  defp looks_like_alias?(input), do: Regex.match?(@name_regex, input)

  # `{:error, _}` is not cached, so a caller never silently sees an empty mapping.
  defp aliases() do
    Sanbase.Cache.get_or_store({@cache_key, @cache_ttl_seconds}, fn -> load_aliases() end)
  end

  defp load_aliases() do
    rows = Repo.all(__MODULE__)

    {:ok,
     %{
       by_num: Map.new(rows, &{&1.version_num, &1}),
       by_name: Map.new(rows, &{&1.version_name, &1.version_num})
     }}
  rescue
    e ->
      Logger.error("Failed to load metric version aliases: #{Exception.message(e)}")
      {:error, :version_aliases_unavailable}
  end

  defp unknown_name_error(metric, name, by_name) do
    known = by_name |> Map.keys() |> Enum.sort() |> Enum.join(", ")

    "#{inspect(name)} is not a version name of #{metric}. Known names: #{known}. " <>
      "Numeric versions are always accepted."
  end
end
