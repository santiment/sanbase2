defmodule SanbaseWeb.Graphql.HistoricalBalanceTypes do
  use Absinthe.Schema.Notation

  object :slug_balance do
    field(:slug, non_null(:string))
    field(:balance, non_null(:float))
  end

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end

  input_object :historical_balance_selector do
    field(:infrastructure, non_null(:string))
    field(:address, non_null(:string))
    field(:currency, :string)
    field(:contract, :string)
  end

  object :miners_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end
end
