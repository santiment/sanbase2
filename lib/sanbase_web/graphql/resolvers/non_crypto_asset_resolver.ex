defmodule SanbaseWeb.Graphql.Resolvers.NonCryptoAssetResolver do
  alias Sanbase.NonCryptoAsset

  def all_non_crypto_assets(_root, args, _resolution) do
    opts =
      case Map.get(args, :asset_type) do
        nil -> []
        asset_type -> [asset_type: asset_type]
      end

    {:ok, NonCryptoAsset.list(opts)}
  end

  def non_crypto_asset_by_slug(_root, %{slug: slug}, _resolution) do
    case NonCryptoAsset.by_slug(slug) do
      nil -> {:error, "Non-crypto asset with slug #{slug} not found."}
      asset -> {:ok, asset}
    end
  end
end
