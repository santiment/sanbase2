defmodule SanbaseWeb.Graphql.Schema.NonCryptoAssetQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.NonCryptoAssetResolver

  object :non_crypto_asset_queries do
    @desc ~s"""
    Fetch all non-crypto assets (stocks, commodities, indices, forex, funds,
    bonds), optionally filtered by asset type.
    """
    field :all_non_crypto_assets, list_of(:non_crypto_asset) do
      meta(access: :free)

      arg(:asset_type, :non_crypto_asset_type)

      cache_resolve(&NonCryptoAssetResolver.all_non_crypto_assets/3)
    end

    @desc "Fetch a non-crypto asset by its slug."
    field :non_crypto_asset_by_slug, :non_crypto_asset do
      meta(access: :free)

      arg(:slug, non_null(:string))

      cache_resolve(&NonCryptoAssetResolver.non_crypto_asset_by_slug/3)
    end
  end
end
