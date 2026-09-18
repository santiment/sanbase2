defmodule Sanbase.Metric.VersionAlias do
  @moduledoc ~s"""
  Human-readable names for metric versions: "2.1" is "modern_pit:v1".

  Names always end in `:vN`, so they can never be mistaken for a version as
  ClickHouse reports it ("2.1", "Experimental (Weighted Age)"). Versions without
  a row pass through untouched - the table is a list of aliases, not an allowlist.

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

  @scopes ["global"]

  # Same list as the seed in the migration that created the table.
  @default_aliases [
    {"1.0", "original:v1", "The original computation. For most metrics the only version."},
    {"2.0", "modern:v1", "Modern computation, v1."},
    {"2.1", "modern_pit:v1", "Point-in-time variant of the modern computation, v1."},
    {"2.1.1", "modern_pit:v1.1", "Point-in-time variant of the modern computation, v1.1."},
    {"2.1.2", "modern_pit:v1.2", "Point-in-time variant of the modern computation, v1.2."},
    {"3.0", "stock:v1", "Stock computation, v1."},
    {"3.1", "stock_pit:v1", "Point-in-time variant of the stock computation, v1."},
    {"Experimental (Weighted Age)", "experimental_weighted_age:v1",
     "Experimental weighted-age implementation. Visible to alpha users only."}
  ]

  @name_regex ~r/^[a-z][a-z0-9_]*:v\d+(\.\d+)*$/
  @term_key {__MODULE__, :aliases}

  schema "metric_version_aliases" do
    field(:scope, :string, default: "global")
    field(:version_num, :string)
    field(:version_name, :string)
    field(:description, :string)

    timestamps()
  end

  @spec list_scopes() :: [String.t()]
  def list_scopes(), do: @scopes

  @doc "Insert the default rows, skipping any that collide with an existing one. Idempotent."
  @spec seed_defaults() :: :ok
  def seed_defaults() do
    now = NaiveDateTime.utc_now() |> NaiveDateTime.truncate(:second)

    entries =
      for {num, name, description} <- @default_aliases do
        %{
          scope: "global",
          version_num: num,
          version_name: name,
          description: description,
          inserted_at: now,
          updated_at: now
        }
      end

    Repo.insert_all(__MODULE__, entries, on_conflict: :nothing)

    clear_cache()
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
    |> validate_version_num()
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

  defp validate_version_num(changeset) do
    num = get_field(changeset, :version_num)

    if is_binary(num) and name?(num),
      do: add_error(changeset, :version_num, "looks like a name, not a version"),
      else: changeset
  end

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
    if name?(input), do: resolve_name(input), else: {:ok, input}
  end

  defp resolve_name(name) do
    case aliases() do
      {:ok, %{by_name: by_name}} ->
        case Map.fetch(by_name, name) do
          {:ok, num} -> {:ok, num}
          :error -> {:error, unknown_name_error(name, by_name)}
        end

      {:error, reason} ->
        Logger.error("Cannot resolve metric version name #{inspect(name)}: #{inspect(reason)}")

        {:error,
         "Version names cannot be resolved at the moment. Use the numeric version instead."}
    end
  end

  @doc "Versions decorated for `availableVersions`. The name falls back to the version itself."
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

  defp name?(input), do: Regex.match?(@name_regex, input)

  defp aliases() do
    case :persistent_term.get(@term_key, :undefined) do
      :undefined ->
        with {:ok, aliases} <- load_aliases() do
          :persistent_term.put(@term_key, aliases)
          {:ok, aliases}
        end

      aliases ->
        {:ok, aliases}
    end
  end

  defp load_aliases() do
    rows = Repo.all(from(a in __MODULE__, where: a.scope == "global"))

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

  defp unknown_name_error(name, by_name) do
    known = by_name |> Map.keys() |> Enum.sort() |> Enum.join(", ")

    "#{inspect(name)} is not a known version name. Known names: #{known}. " <>
      "Numeric versions are always accepted."
  end
end
