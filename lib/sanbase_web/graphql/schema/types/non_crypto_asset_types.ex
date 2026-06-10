defmodule SanbaseWeb.Graphql.NonCryptoAssetTypes do
  use Absinthe.Schema.Notation

  enum :non_crypto_asset_type do
    value(:stock)
    value(:commodity)
    value(:index)
    value(:forex)
    value(:fund)
    value(:bond)
    value(:other)
  end

  @desc ~s"""
  A non-crypto asset tracked by Sanbase — a stock, commodity, index, forex
  pair, fund or bond (e.g. the non-crypto instruments tradeable on
  Hyperliquid).
  """
  object :non_crypto_asset do
    field(:id, non_null(:id))
    field(:slug, non_null(:string))
    field(:name, non_null(:string))
    field(:ticker, :string)
    field(:asset_type, non_null(:non_crypto_asset_type))
    field(:description, :string)
    field(:logo_url, :string)
    field(:website_link, :string)
  end
end
