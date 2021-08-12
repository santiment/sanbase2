defmodule SanbaseWeb.Graphql.TransferTypes do
  use Absinthe.Schema.Notation

  object :address_watchlist_subtype do
    field(:id, :integer)
    field(:name, :string)
    field(:slug, :string)
  end

  object :account_based_transfer do
    field(:datetime, non_null(:datetime))
    field(:trx_hash, non_null(:string))
    field(:trx_value, non_null(:float))
    field(:from_address, :blockchain_address_ephemeral)
    field(:to_address, :blockchain_address_ephemeral)
  end
end
