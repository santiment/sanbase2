defmodule SanbaseWeb.Graphql.NftTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.ProjectResolver

  enum :sort_direction do
    value(:asc)
    value(:desc)
  end

  enum :nft_trade_label_key do
    value(:nft_influencer)
  end

  input_object :nft_contract_input_object do
    field(:address, non_null(:string))
    field(:infrastructure, :string)
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
    field(:name, :string)
  end

  object :nft_quantity do
    field(:token_id, non_null(:string))
    field(:quantity, non_null(:float))
  end

  object :nft_trade do
    field(:trx_hash, :string)
    field(:marketplace, :string)

    @desc ~s"""
    The currency project refers to the currency that the NFT is paid for with.
    This project is **not** describing the NFT being transferred
    """
    field :currency_project, :project do
      resolve(&ProjectResolver.nft_project_by_slug/3)
    end

    field(:from_address, :nft_trader)
    field(:to_address, :nft_trader)
    field(:datetime, :datetime)
    field(:amount, :float)
    field(:quantity, :float)
    field(:quantities, list_of(:nft_quantity))
    field(:nft, :nft)
  end

  object :nft_contract_data do
    field(:nft_collection, :string)
  end
end
