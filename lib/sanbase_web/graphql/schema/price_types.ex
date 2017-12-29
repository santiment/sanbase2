defmodule SanbaseWeb.Graphql.PriceTypes do
  use Absinthe.Schema.Notation

  object :price_point do
    field(:datetime, non_null(:datetime))
    field(:marketcap, :decimal)
    field(:price_usd, :decimal)
    field(:price_btc, :decimal)
    field(:volume, :decimal)
  end
end