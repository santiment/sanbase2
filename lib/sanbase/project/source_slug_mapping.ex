defmodule Sanbase.Project.SourceSlugMapping do
  use Ecto.Schema

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Repo
  alias Sanbase.Project

  @table "source_slug_mappings"

  schema @table do
    field(:source, :string)
    field(:slug, :string)

    belongs_to(:project, Project)
    belongs_to(:non_crypto_asset, Sanbase.NonCryptoAsset)
  end

  def changeset(%__MODULE__{} = ssm, attrs \\ %{}) do
    ssm
    |> cast(attrs, [:source, :slug, :project_id, :non_crypto_asset_id])
    |> validate_required([:source, :slug])
    |> validate_exactly_one_asset_reference()
    |> check_constraint(:project_id, name: :exactly_one_asset_reference)
    |> unique_constraint(:non_crypto_asset_id, name: :one_mapping_per_source_non_crypto_asset)
  end

  defp validate_exactly_one_asset_reference(changeset) do
    project_id = get_field(changeset, :project_id)
    non_crypto_asset_id = get_field(changeset, :non_crypto_asset_id)

    case {project_id, non_crypto_asset_id} do
      {nil, nil} ->
        add_error(changeset, :project_id, "either project or non-crypto asset must be set")

      {p, n} when not is_nil(p) and not is_nil(n) ->
        add_error(changeset, :project_id, "cannot set both project and non-crypto asset")

      _ ->
        changeset
    end
  end

  def create(attrs) do
    changeset(%__MODULE__{}, attrs) |> Repo.insert()
  end

  def remove(project_id, source) do
    from(
      ssm in __MODULE__,
      where: ssm.project_id == ^project_id and ssm.source == ^source
    )
    |> Repo.delete_all()
  end

  @type return_filter :: :crypto_project_only | :non_crypto_project_only | :all

  @doc ~s"""
  Return `{source_slug, sanbase_slug}` pairs for `source`.

  The `:return` option selects which mappings are included:

    * `:crypto_project_only` (default) — only rows mapped to a crypto `Project`.
      This is the historical behaviour, kept as the default so project-coupled
      callers never accidentally pick up non-crypto assets.
    * `:non_crypto_project_only` — only rows mapped to a `Sanbase.NonCryptoAsset`.
    * `:all` — both, with `sanbase_slug` taken from whichever reference is set.
  """
  @spec get_source_slug_mappings(String.t(), [{:return, return_filter()}]) ::
          [{String.t(), String.t()}]
  def get_source_slug_mappings(source, opts \\ []) do
    opts
    |> Keyword.get(:return, :crypto_project_only)
    |> source_slug_mappings_query(source)
    |> Repo.all()
  end

  defp source_slug_mappings_query(:crypto_project_only, source) do
    from(
      ssm in __MODULE__,
      join: p in assoc(ssm, :project),
      where: ssm.source == ^source,
      select: {ssm.slug, p.slug}
    )
  end

  defp source_slug_mappings_query(:non_crypto_project_only, source) do
    from(
      ssm in __MODULE__,
      join: nca in assoc(ssm, :non_crypto_asset),
      where: ssm.source == ^source,
      select: {ssm.slug, nca.slug}
    )
  end

  defp source_slug_mappings_query(:all, source) do
    from(
      ssm in __MODULE__,
      left_join: p in assoc(ssm, :project),
      left_join: nca in assoc(ssm, :non_crypto_asset),
      where: ssm.source == ^source,
      select: {ssm.slug, coalesce(p.slug, nca.slug)}
    )
  end

  def get_slug(%Project{id: project_id}, source) do
    from(
      ssm in __MODULE__,
      where: ssm.project_id == ^project_id and ssm.source == ^source,
      select: ssm.slug
    )
    |> Repo.one()
  end

  @doc ~s"""
  Return the source slug (as known to `source`) for the project or non-crypto
  asset identified by `sanbase_slug`, or `nil` if no mapping exists.
  """
  @spec get_source_slug(String.t(), String.t()) :: String.t() | nil
  def get_source_slug(sanbase_slug, source) do
    from(
      ssm in __MODULE__,
      left_join: p in assoc(ssm, :project),
      left_join: nca in assoc(ssm, :non_crypto_asset),
      where: ssm.source == ^source and coalesce(p.slug, nca.slug) == ^sanbase_slug,
      select: ssm.slug,
      limit: 1
    )
    |> Repo.one()
  end

  def delete_mappings_for_source_and_slugs(source, slugs) do
    from(
      ssm in __MODULE__,
      where: ssm.source == ^source and ssm.slug in ^slugs
    )
    |> Repo.delete_all()
  end
end
