defmodule Sanbase.Metric.VersionAlias do
  @moduledoc ~s"""
  Human-readable names for metric versions: "2.1" is "modern_pit:v1".

  Names always end in `:vN`, so they can never be mistaken for a version ("2.1",
  "Experimental (Weighted Age)"). Versions without a row pass through untouched -
  the table is a list of aliases, not an allowlist.

  Applied only at the GraphQL boundary (`to_version_num/1` on the way in,
  `to_maps/1` on the way out) from a single `:persistent_term`; everything in
  between keeps seeing the canonical version. Every row has `scope` "global";
  the column is the seam for per-category or per-metric names later.
  """

  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, only: [from: 2]

  require Logger

  alias Sanbase.Repo

  @type t :: %__MODULE__{}

  @name_regex ~r/^[a-z][a-z0-9_]*:v\d+(\.\d+)*$/
  @term_key {__MODULE__, :aliases}

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
    |> validate_inclusion(:scope, ["global"])
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
  @spec to_version_num(String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def to_version_num(input) when is_binary(input) do
    %{by_name: by_name} = aliases()

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
  @spec to_maps([String.t()]) :: [map()]
  def to_maps(versions) when is_list(versions) do
    %{by_num: by_num} = aliases()

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

  defp name?(input), do: Regex.match?(@name_regex, input)

  defp aliases() do
    case :persistent_term.get(@term_key, :undefined) do
      :undefined -> load_aliases()
      aliases -> aliases
    end
  end

  # Nothing is stored on failure, so the next read retries.
  defp load_aliases() do
    rows = Repo.all(from(a in __MODULE__, where: a.scope == "global"))

    aliases = %{
      by_num: Map.new(rows, &{&1.version_num, &1}),
      by_name: Map.new(rows, &{&1.version_name, &1.version_num})
    }

    :persistent_term.put(@term_key, aliases)
    aliases
  rescue
    e ->
      Logger.error("Failed to load metric version aliases: #{Exception.message(e)}")
      %{by_num: %{}, by_name: %{}}
  end
end
