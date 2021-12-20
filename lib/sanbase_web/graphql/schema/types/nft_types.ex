defmodule SanbaseWeb.Graphql.NftTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ProjectResolver

  enum :nft_trade_label_key do
    value(:nft_influencer)
  end

  enum :nft_trades_order_by do
    value(:datetime)
    value(:amount)
  end

  object :nft_trader do
    field(:address, :string)
    field(:label_key, :nft_trade_label_key)
  end

  object :nft do
    field(:contract_address, :string)
  end

  object :nft_trade do
    field(:trx_hash, :string)
    field(:marketplace, :string)

    @desc ~s"""
    The currency project refers to the currency that the NFT is paid for with.
    This project is **not** describing the NFT being transferred
    """
    field :currency_project, :project do
      resolve(&ProjectResolver.project_by_slug/3)
    end

    field(:from_address, :nft_trader)
    field(:to_address, :nft_trader)
    field(:datetime, :datetime)
    field(:amount, :float)
    field(:nft, :nft)
  end
end
