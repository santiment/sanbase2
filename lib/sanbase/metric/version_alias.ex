defmodule Sanbase.Metric.VersionAlias do
  @moduledoc ~s"""
  Human-readable names for metric versions: "2.1" is "modern_pit:v1".

  Names always end in `:vN`, so they can never be mistaken for a version ("2.1",
  "Experimental (Weighted Age)"). Versions without a row pass through untouched -
  the table is a list of aliases, not an allowlist.

  Applied only at the GraphQL boundary (`to_version_num/2` on the way in,
  `to_maps/2` on the way out) from a single `:persistent_term`; everything in
  between keeps seeing the canonical version.

  Every row belongs to a scope (see `Sanbase.Metric.version_scope/1`). A scope sees
  its own rows and the "global" ones; its own win for the same version.

  A row also says where the version can be used (`exposed_in`) and which plans may
  use it (`plan_access`, see `Sanbase.Metric.VersionPlanAccess`). Both are enforced by
  `Sanbase.Billing.Plan.MetricVersionAccess`.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Repo
  alias Sanbase.Metric.VersionPlanAccess

  @type t :: %__MODULE__{}

  @name_regex ~r/^[a-z][a-z0-9_]*:v\d+(\.\d+)*$/
  @term_key {__MODULE__, :aliases}

  @scopes ["global", "github", "social"]
  @no_aliases %{by_num: %{}, by_name: %{}}

  # The products a version can be used in, keyed by `exposed_in`.
  @exposures %{
    "all" => ["SANAPI", "SANBASE"],
    "api_only" => ["SANAPI"],
    "sanbase_only" => ["SANBASE"]
  }

  @doc "The scopes a row can belong to."
  @spec scopes() :: [String.t()]
  def scopes(), do: @scopes

  @doc "The values of `exposed_in`."
  @spec exposures() :: [String.t()]
  def exposures(), do: Map.keys(@exposures)

  schema "metric_version_aliases" do
    field(:scope, :string, default: "global")
    field(:version_num, :string)
    field(:version_name, :string)
    field(:description, :string)
    field(:exposed_in, :string, default: "all")

    has_many(:plan_access, VersionPlanAccess)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = version_alias, attrs) do
    version_alias
    |> cast(attrs, [:scope, :version_num, :version_name, :description, :exposed_in])
    |> update_change(:version_num, &trim/1)
    |> update_change(:version_name, &trim/1)
    |> validate_required([:scope, :version_num, :version_name, :exposed_in])
    |> validate_inclusion(:scope, @scopes)
    |> validate_inclusion(:exposed_in, Map.keys(@exposures))
    |> validate_default_version_exposed()
    |> validate_format(:version_name, @name_regex,
      message: "must look like modern_pit:v1 - lowercase, digits, underscores, then :vN or :vN.N"
    )
    |> validate_change(:version_num, fn :version_num, num ->
      if name?(num), do: [version_num: "looks like a name, not a version"], else: []
    end)
    |> unique_constraint([:scope, :version_num],
      error_key: :version_num,
      message: "already has a name"
    )
    |> unique_constraint([:scope, :version_name],
      error_key: :version_name,
      message: "is already the name of another version"
    )
  end

  # Requests without a version get the default one, so it has to work everywhere.
  defp validate_default_version_exposed(changeset) do
    if get_field(changeset, :version_num) == Sanbase.Metric.default_version() and
         get_field(changeset, :exposed_in) != "all" do
      add_error(changeset, :exposed_in, "must be all for the default version")
    else
      changeset
    end
  end

  # A cleared form field arrives as a change to nil.
  defp trim(nil), do: nil
  defp trim(string), do: String.trim(string)

  @doc "Drop the cached rows on every node; each reloads on its next read."
  @spec clear_cache() :: :ok
  def clear_cache() do
    :persistent_term.erase(@term_key)

    for node <- Node.list() do
      Node.spawn(node, :persistent_term, :erase, [@term_key])
    end

    :ok
  end

  @doc "Name to canonical version. Anything not shaped like a name passes through."
  @spec to_version_num(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def to_version_num(input, scope \\ "global") when is_binary(input) do
    %{by_name: by_name} = aliases(scope)

    cond do
      not name?(input) ->
        {:ok, input}

      Map.has_key?(by_name, input) ->
        {:ok, by_name[input]}

      true ->
        known = by_name |> Map.keys() |> Enum.sort() |> Enum.join(", ")

        {:error,
         "#{inspect(input)} is not a known version name. Known names: #{known}. " <>
           "Numeric versions are always accepted."}
    end
  end

  @doc "Versions decorated for `availableVersions`. The name falls back to the version itself."
  @spec to_maps([String.t()], String.t()) :: [map()]
  def to_maps(versions, scope \\ "global") when is_list(versions) do
    %{by_num: by_num} = aliases(scope)

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

  @doc "Canonical version to its name. Falls back to the version itself."
  @spec to_version_name(String.t(), String.t()) :: String.t()
  def to_version_name(version_num, scope \\ "global") when is_binary(version_num) do
    %{by_num: by_num} = aliases(scope)

    case Map.get(by_num, version_num) do
      %{version_name: name} -> name
      nil -> version_num
    end
  end

  @doc "The row of a canonical version, with its `plan_access`, or nil."
  @spec get(String.t(), String.t()) :: t() | nil
  def get(version_num, scope \\ "global") when is_binary(version_num) do
    %{by_num: by_num} = aliases(scope)
    Map.get(by_num, version_num)
  end

  @doc "Every row the scope sees."
  @spec rows(String.t()) :: [t()]
  def rows(scope \\ "global") do
    %{by_num: by_num} = aliases(scope)
    Map.values(by_num)
  end

  @doc "Every row of every scope with its `plan_access`, read from the database."
  @spec list_with_plan_access() :: [t()]
  def list_with_plan_access() do
    from(a in __MODULE__, preload: :plan_access)
    |> Repo.all()
    |> Enum.sort_by(
      &{Enum.find_index(@scopes, fn s -> s == &1.scope end), sort_key(&1.version_num)}
    )
  end

  @doc "The row with its `plan_access`, read from the database."
  @spec get_with_plan_access!(integer() | String.t()) :: t()
  def get_with_plan_access!(id), do: __MODULE__ |> Repo.get!(id) |> Repo.preload(:plan_access)

  @spec create(map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(attrs) do
    %__MODULE__{}
    |> changeset(attrs)
    |> Repo.insert()
    |> tap(&clear_cache_on_ok/1)
  end

  @doc """
  Update the row. Plan access for a product the version is no longer exposed in is
  deleted with it - it could never match, and would come back silently if the
  version were exposed there again.
  """
  @spec update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def update(%__MODULE__{} = version_alias, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.update(:version_alias, changeset(version_alias, attrs))
    |> Ecto.Multi.delete_all(:unexposed_plan_access, fn %{version_alias: updated} ->
      from(p in VersionPlanAccess,
        where:
          p.version_alias_id == ^updated.id and
            p.product not in ^Map.fetch!(@exposures, updated.exposed_in)
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{version_alias: updated}} ->
        clear_cache()
        {:ok, updated}

      {:error, :version_alias, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc "Delete the row and its plan access."
  @spec delete(t()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def delete(%__MODULE__{} = version_alias) do
    version_alias |> Repo.delete() |> tap(&clear_cache_on_ok/1)
  end

  defp clear_cache_on_ok({:ok, _}), do: clear_cache()
  defp clear_cache_on_ok(_), do: :ok

  @doc """
  Sorts versions numerically ("2.0" before "10.0"). Non-numeric parts
  ("Experimental (Weighted Age)") sort first instead of raising.
  """
  @spec sort_key(String.t()) :: [integer()]
  def sort_key(version) do
    version
    |> String.split(".")
    |> Enum.map(fn part ->
      case Integer.parse(part) do
        {int, ""} -> int
        _ -> -1
      end
    end)
  end

  @doc """
  Whether the version can be used in the product ("SANAPI" or "SANBASE"). A version
  without a row is exposed everywhere.
  """
  @spec exposed_in?(t() | nil, String.t()) :: boolean()
  def exposed_in?(nil, _product), do: true

  def exposed_in?(%__MODULE__{exposed_in: exposed_in}, product),
    do: product in Map.get(@exposures, exposed_in, [])

  @doc "Every canonical version that has a name."
  @spec version_nums(String.t()) :: [String.t()]
  def version_nums(scope \\ "global") do
    %{by_num: by_num} = aliases(scope)
    Map.keys(by_num)
  end

  defp name?(input), do: Regex.match?(@name_regex, input)

  defp aliases(scope) do
    aliases_by_scope =
      case :persistent_term.get(@term_key, :undefined) do
        :undefined -> load_aliases()
        aliases_by_scope -> aliases_by_scope
      end

    Map.get(aliases_by_scope, scope, @no_aliases)
  end

  # Nothing is stored on failure, so the next read retries.
  defp load_aliases() do
    rows_by_scope =
      Repo.all(from(a in __MODULE__, where: a.scope in ^@scopes, preload: :plan_access))
      |> Enum.group_by(& &1.scope)

    global_rows = Map.get(rows_by_scope, "global", [])

    aliases_by_scope =
      Map.new(@scopes, fn
        "global" -> {"global", index(global_rows)}
        scope -> {scope, index(global_rows ++ Map.get(rows_by_scope, scope, []))}
      end)

    :persistent_term.put(@term_key, aliases_by_scope)
    aliases_by_scope
  rescue
    e ->
      Logger.error("Failed to load metric version aliases: #{Exception.message(e)}")
      %{}
  end

  # Later rows win, and the name of an overridden row is dropped with it.
  defp index(rows) do
    by_num = Map.new(rows, &{&1.version_num, &1})

    by_name =
      rows
      |> Enum.filter(&(by_num[&1.version_num] == &1))
      |> Map.new(&{&1.version_name, &1.version_num})

    %{by_num: by_num, by_name: by_name}
  end
end
