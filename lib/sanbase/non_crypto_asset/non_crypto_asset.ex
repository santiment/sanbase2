defmodule Sanbase.NonCryptoAsset do
  @moduledoc ~s"""
  Non-crypto assets (stocks, commodities, indices, forex, funds, bonds) that
  Sanbase tracks — e.g. the non-crypto instruments tradeable on Hyperliquid.

  Kept separate from `Sanbase.Project`, which carries crypto-specific fields
  (contracts, infrastructure, coinmarketcap id, ICOs) that do not apply here.
  Slugs share a single namespace with project slugs — slug-keyed APIs must
  resolve to exactly one asset — so the changeset rejects slugs already taken
  by a project.
  """

  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Sanbase.Repo

  @asset_types [:stock, :commodity, :index, :forex, :fund, :bond, :other]

  schema "non_crypto_assets" do
    field(:slug, :string)
    field(:name, :string)
    field(:ticker, :string)
    field(:asset_type, Ecto.Enum, values: @asset_types)
    field(:description, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
    field(:is_hidden, :boolean, default: false)
    field(:hidden_since, :utc_datetime)
    field(:hidden_reason, :string)
    field(:metadata, :map, default: %{})

    has_many(:source_slug_mappings, Sanbase.Project.SourceSlugMapping)

    timestamps()
  end

  @type t :: %__MODULE__{}

  def asset_types(), do: @asset_types

  def changeset(%__MODULE__{} = asset, attrs \\ %{}) do
    asset
    |> cast(attrs, [
      :slug,
      :name,
      :ticker,
      :asset_type,
      :description,
      :logo_url,
      :website_link,
      :is_hidden,
      :hidden_since,
      :hidden_reason,
      :metadata
    ])
    |> validate_required([:slug, :name, :asset_type])
    |> unique_constraint(:slug)
    |> validate_no_project_slug_collision()
    |> maybe_add_hidden_since()
  end

  def create(attrs) do
    changeset(%__MODULE__{}, attrs) |> Repo.insert()
  end

  @spec by_slug(String.t()) :: %__MODULE__{} | nil
  def by_slug(slug) when is_binary(slug) do
    Repo.get_by(__MODULE__, slug: slug)
  end

  @spec id_by_slug(String.t()) :: non_neg_integer() | nil
  def id_by_slug(slug) when is_binary(slug) do
    from(a in __MODULE__, where: a.slug == ^slug, select: a.id) |> Repo.one()
  end

  @spec by_slugs([String.t()]) :: [t()]
  def by_slugs(slugs) when is_list(slugs) do
    from(a in __MODULE__, where: a.slug in ^slugs, order_by: [asc: a.name])
    |> Repo.all()
  end

  @doc ~s"""
  List non-crypto assets ordered by name.

  Options:
    * `:asset_type` — only assets of the given type
    * `:include_hidden` — include hidden assets, defaults to `false`
  """
  @spec list(Keyword.t()) :: [%__MODULE__{}]
  def list(opts \\ []) do
    base_query(opts)
    |> order_by([a], asc: a.name)
    |> Repo.all()
  end

  @doc ~s"""
  Slugs of all visible non-crypto assets.
  """
  @spec slugs() :: [String.t()]
  def slugs() do
    base_query([])
    |> select([a], a.slug)
    |> Repo.all()
  end

  defp base_query(opts) do
    __MODULE__
    |> maybe_filter_asset_type(Keyword.get(opts, :asset_type))
    |> maybe_exclude_hidden(Keyword.get(opts, :include_hidden, false))
  end

  defp maybe_filter_asset_type(query, nil), do: query

  defp maybe_filter_asset_type(query, asset_type) do
    where(query, [a], a.asset_type == ^asset_type)
  end

  defp maybe_exclude_hidden(query, true), do: query
  defp maybe_exclude_hidden(query, false), do: where(query, [a], a.is_hidden == false)

  defp maybe_add_hidden_since(changeset) do
    case changeset.changes do
      %{is_hidden: true} ->
        put_change(changeset, :hidden_since, DateTime.utc_now() |> DateTime.truncate(:second))

      %{is_hidden: false} ->
        put_change(changeset, :hidden_since, nil)

      _ ->
        changeset
    end
  end

  defp validate_no_project_slug_collision(changeset) do
    case get_change(changeset, :slug) do
      nil ->
        changeset

      slug ->
        case Sanbase.Project.id_by_slug(slug) do
          nil -> changeset
          _id -> add_error(changeset, :slug, "already used by a project")
        end
    end
  end
end
