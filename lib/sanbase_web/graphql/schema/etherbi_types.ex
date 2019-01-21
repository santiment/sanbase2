defmodule SanbaseWeb.Graphql.EtherbiTypes do
  use Absinthe.Schema.Notation

  object :token_age_consumed_data do
    field(:datetime, non_null(:datetime))
    field(:token_age_consumed, :float)
  end

  object :burn_rate_data do
    field(:datetime, non_null(:datetime))
    field(:burn_rate, :float)
  end

  object :transaction_volume do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume, :float)
  end

  object :active_addresses do
    field(:datetime, non_null(:datetime))
    field(:active_addresses, non_null(:integer))
  end

  object :token_age do
    field(:datetime, non_null(:datetime))
    field(:token_age, non_null(:float))
  end

  object :wallet do
    field(:name, non_null(:string))
    field(:address, non_null(:string))
    field(:is_dex, :boolean)
    field(:infrastructure, :infrastructure)
  end

  object :infrastructure do
    field(:id, non_null(:integer))
    field(:code, non_null(:string))
  end

  object :token_circulation do
    field(:datetime, non_null(:datetime))
    field(:token_circulation, :float)
  end

  object :token_velocity do
    field(:datetime, non_null(:datetime))
    field(:token_velocity, :float)
  end
end
