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
    # Hidden assets are not served, matching the visibility behaviour of the list
    # endpoints, but a hidden asset reports a distinct error from a missing one.
    case NonCryptoAsset.by_slug(slug) do
      %{is_hidden: false} = asset -> {:ok, asset}
      %{is_hidden: true} -> {:error, "Non-crypto asset with slug #{slug} is hidden."}
      nil -> {:error, "Non-crypto asset with slug #{slug} not found."}
    end
  end
end
