defmodule SanbaseWeb.Graphql.EtherbiTypes do
  use Absinthe.Schema.Notation

  object :burn_rate_data do
    field(:datetime, non_null(:datetime))
    field(:burn_rate, :decimal)
  end

  object :transaction_volume do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :decimal)
  end

  object :transaction do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :decimal)
    field(:address, :string)
  end

  enum :transaction_type do
    value(:in)
    value(:out)
    value(:all)
  end
end
