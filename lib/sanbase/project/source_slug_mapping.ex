defmodule Sanbase.Project.SourceSlugMapping do
  use Ecto.Schema

  require Logger

  import Ecto.Query
  import Ecto.Changeset

  alias Sanbase.Hyperliquid.Bbo.CoinUniverse
  alias Sanbase.Repo
  alias Sanbase.Project

  @hyperliquid_source "hyperliquid"

  @table "source_slug_mappings"

  schema @table do
    field(:source, :string)
    field(:slug, :string)

    # Transient marker set by the changeset when a hyperliquid coin could not
    # be verified against HL's universe in time. Read by the admin
    # `after_filter/3` to surface a warning; never persisted.
    field(:coin_verification, :string, virtual: true)

    belongs_to(:project, Project)
    belongs_to(:non_crypto_asset, Sanbase.NonCryptoAsset)
  end

  def changeset(%__MODULE__{} = ssm, attrs \\ %{}) do
    ssm
    |> cast(attrs, [:source, :slug, :project_id, :non_crypto_asset_id])
    |> validate_required([:source, :slug])
    |> validate_exactly_one_asset_reference()
    |> validate_hyperliquid_coin()
    |> check_constraint(:project_id, name: :exactly_one_asset_reference)
    |> unique_constraint(:non_crypto_asset_id, name: :one_mapping_per_source_non_crypto_asset)
  end

  # For a new/changed `hyperliquid` mapping, block the write when Hyperliquid
  # confirms the coin does not exist, and allow-but-warn when HL can't be
  # reached in time. Only Hyperliquid can authoritatively say a coin is bad, so
  # this is the one place that consults it synchronously. No network call is
  # made for other sources, empty slugs, or unrelated changesets.
  defp validate_hyperliquid_coin(changeset) do
    slug = get_field(changeset, :slug)
    source = get_field(changeset, :source)
    slug_or_source_changed? = changed?(changeset, :slug) or changed?(changeset, :source)

    if changeset.valid? and slug_or_source_changed? and source == @hyperliquid_source and
         is_binary(slug) and CoinUniverse.verify_on_write?() do
      case CoinUniverse.coin_supported?(slug) do
        :ok ->
          changeset

        {:unsupported, reason, suggestions} ->
          add_error(changeset, :slug, unsupported_coin_message(slug, reason, suggestions))

        :unverified ->
          Logger.warning(
            "[SourceSlugMapping] could not verify hyperliquid coin \"#{slug}\" against the HL universe (timeout/fetch error); saving without verification"
          )

          put_change(changeset, :coin_verification, "unverified")
      end
    else
      changeset
    end
  end

  defp unsupported_coin_message(slug, :spot_token_only, []) do
    "\"#{slug}\" exists on Hyperliquid only as a spot token — it has no perp market " <>
      "and no spot pair, so the bbo stream cannot carry it"
  end

  defp unsupported_coin_message(slug, :spot_token_only, pairs) do
    "\"#{slug}\" exists on Hyperliquid only as a spot token (no perp market); " <>
      "the bbo stream needs a tradeable pair name — map it as: #{Enum.join(pairs, ", ")}"
  end

  defp unsupported_coin_message(slug, :not_in_universe, []) do
    "\"#{slug}\" is not a coin in the Hyperliquid universe"
  end

  defp unsupported_coin_message(slug, :not_in_universe, suggestions) do
    unsupported_coin_message(slug, :not_in_universe, []) <>
      " (did you mean: #{Enum.join(suggestions, ", ")}?)"
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

  The `:include_hidden` option controls whether mappings of hidden projects /
  non-crypto assets are included. It defaults to `false` — hidden assets are
  excluded unless `include_hidden: true` is passed explicitly.
  """
  @spec get_source_slug_mappings(String.t(), [
          {:return, return_filter()} | {:include_hidden, boolean()}
        ]) :: [{String.t(), String.t()}]
  def get_source_slug_mappings(source, opts \\ []) do
    return = Keyword.get(opts, :return, :crypto_project_only)
    include_hidden = Keyword.get(opts, :include_hidden, false)

    return
    |> source_slug_mappings_query(source)
    |> maybe_exclude_hidden(return, include_hidden)
    |> Repo.all()
  end

  defp source_slug_mappings_query(:crypto_project_only, source) do
    from(
      ssm in __MODULE__,
      join: p in assoc(ssm, :project),
      as: :project,
      where: ssm.source == ^source,
      select: {ssm.slug, p.slug}
    )
  end

  defp source_slug_mappings_query(:non_crypto_project_only, source) do
    from(
      ssm in __MODULE__,
      join: nca in assoc(ssm, :non_crypto_asset),
      as: :non_crypto_asset,
      where: ssm.source == ^source,
      select: {ssm.slug, nca.slug}
    )
  end

  defp source_slug_mappings_query(:all, source) do
    from(
      ssm in __MODULE__,
      left_join: p in assoc(ssm, :project),
      as: :project,
      left_join: nca in assoc(ssm, :non_crypto_asset),
      as: :non_crypto_asset,
      where: ssm.source == ^source,
      select: {ssm.slug, coalesce(p.slug, nca.slug)}
    )
  end

  defp maybe_exclude_hidden(query, _return, true), do: query

  defp maybe_exclude_hidden(query, :crypto_project_only, false) do
    # projects.is_hidden is nullable; NULL means visible.
    where(query, [project: p], coalesce(p.is_hidden, false) == false)
  end

  defp maybe_exclude_hidden(query, :non_crypto_project_only, false) do
    where(query, [non_crypto_asset: nca], nca.is_hidden == false)
  end

  defp maybe_exclude_hidden(query, :all, false) do
    # Exactly one of p/nca is set per row, so the inner coalesce picks the
    # hidden flag of whichever asset the row references. The outer coalesce
    # to false covers projects.is_hidden being nullable (NULL means visible).
    where(
      query,
      [project: p, non_crypto_asset: nca],
      coalesce(coalesce(p.is_hidden, nca.is_hidden), false) == false
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
