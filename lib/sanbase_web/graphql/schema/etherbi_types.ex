defmodule SanbaseWeb.Graphql.EtherbiTypes do
  use Absinthe.Schema.Notation

  object :burn_rate_data do
    field(:datetime, non_null(:datetime))
    field(:burn_rate, :float)
  end

  object :transaction_volume do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :float)
  end

  object :average_token_age_data do
    field(:datetime, non_null(:datetime))
    field(:average_token_age, :float)
  end

  object :active_addresses do
    field(:datetime, non_null(:datetime))
    field(:active_addresses, non_null(:integer))
  end

  object :wallet do
    field(:name, non_null(:string))
    field(:address, non_null(:string))
  end

  object :token_circulation_data do
    field(:datetime, non_null(:datetime))
    field(:token_circulation, :float)
  end
end
