defmodule SanbaseWeb.Graphql.HistoricalBalanceTypes do
  use Absinthe.Schema.Notation

  alias SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver

  object :slug_balance do
    field(:slug, non_null(:string))
    field(:balance, non_null(:float))

    field :balance_usd, :float do
      resolve(&HistoricalBalanceResolver.balance_usd/3)
    end
  end

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end

  object :address_balance_change do
    field(:address, non_null(:string))
    field(:balance_start, non_null(:float))
    field(:balance_end, non_null(:float))
    field(:balance_change_amount, non_null(:float))
    field(:balance_change_percent, non_null(:float))
  end

  object :address_transaction_volume do
    field(:address, non_null(:string))
    field(:transaction_volume_inflow, non_null(:float))
    field(:transaction_volume_outflow, non_null(:float))
    field(:transaction_volume_total, non_null(:float))
  end

  object :combined_address_transaction_volume_over_time do
    field(:datetime, non_null(:datetime))
    field(:transaction_volume_inflow, non_null(:float))
    field(:transaction_volume_outflow, non_null(:float))
    field(:transaction_volume_total, non_null(:float))
  end

  input_object :address_selector_input_object do
    field(:infrastructure, non_null(:string))
    field(:address, non_null(:string))
  end

  input_object :historical_balance_selector do
    field(:infrastructure, :string)
    field(:currency, :string)
    field(:contract, :string)
    field(:decimals, :integer)
    field(:slug, :string)
  end

  object :miners_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end
end
