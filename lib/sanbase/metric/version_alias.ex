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
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Repo

  @type t :: %__MODULE__{}

  @name_regex ~r/^[a-z][a-z0-9_]*:v\d+(\.\d+)*$/
  @term_key {__MODULE__, :aliases}

  @scopes ["global", "github", "social"]
  @no_aliases %{by_num: %{}, by_name: %{}}

  @doc "The scopes a row can belong to."
  @spec scopes() :: [String.t()]
  def scopes(), do: @scopes

  schema "metric_version_aliases" do
    field(:scope, :string, default: "global")
    field(:version_num, :string)
    field(:version_name, :string)
    field(:description, :string)

    timestamps()
  end

  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = version_alias, attrs) do
    version_alias
    |> cast(attrs, [:scope, :version_num, :version_name, :description])
    |> update_change(:version_num, &trim/1)
    |> update_change(:version_name, &trim/1)
    |> validate_required([:scope, :version_num, :version_name])
    |> validate_inclusion(:scope, @scopes)
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
      Repo.all(from(a in __MODULE__, where: a.scope in ^@scopes))
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
