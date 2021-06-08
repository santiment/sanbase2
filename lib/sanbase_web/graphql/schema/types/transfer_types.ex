defmodule SanbaseWeb.Graphql.TransferTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.BlockchainAddressResolver

  object :address_watchlist_subtype do
    field(:id, :integer)
    field(:name, :string)
    field(:slug, :string)
  end

  object :current_user_address_details do
    field(:watchlists, list_of(:address_watchlist_subtype))
    field(:notes, :string)
  end

  object :account_based_transfer_address do
    field(:address, non_null(:string))
    field(:infrastructure, non_null(:string))
    field(:labels, non_null(list_of(:label)))

    field :current_user_address_details, :current_user_address_details do
      resolve(&BlockchainAddressResolver.current_user_address_details/3)
    end
  end

  object :account_based_transfer do
    field(:datetime, non_null(:datetime))
    field(:trx_hash, non_null(:string))
    field(:trx_value, non_null(:float))
    field(:from_address, :account_based_transfer_address)
    field(:to_address, :account_based_transfer_address)
  end
end
