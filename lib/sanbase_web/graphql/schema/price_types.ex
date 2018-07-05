defmodule SanbaseWeb.Graphql.PriceTypes do
  use Absinthe.Schema.Notation

  object :price_point do
    field(:datetime, non_null(:datetime))
    field(:marketcap, :decimal)
    field(:price_usd, :decimal)
    field(:price_btc, :decimal)
    field(:volume, :decimal)
    field(:ticker, :string)
  end

  object :ohlc do
    field(:datetime, non_null(:datetime))
    field(:open_price_usd, :float)
    field(:high_price_usd, :float)
    field(:low_price_usd, :float)
    field(:close_price_usd, :float)
  end
end
