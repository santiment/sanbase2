defmodule SanbaseWeb.Graphql.TransactionTypes do
  use Absinthe.Schema.Notation

  enum :transaction_type do
    value(:in)
    value(:out)
    value(:all)
  end

  object :wallet_transaction do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :decimal)
    field(:transaction_type, :string)
    field(:from_address, :string)
    field(:to_address, :string)
  end

  object :exchange_transaction do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :float)
    field(:address, :string)
  end
end
