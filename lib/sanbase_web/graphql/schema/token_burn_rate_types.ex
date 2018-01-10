defmodule SanbaseWeb.Graphql.TokenBurnRateTypes do
  use Absinthe.Schema.Notation

  object :burn_rate_data do
    field(:datetime, non_null(:datetime))
    field(:burn_rate, :decimal)
  end
end