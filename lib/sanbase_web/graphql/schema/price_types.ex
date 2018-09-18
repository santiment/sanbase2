defmodule SanbaseWeb.Graphql.PriceTypes do
  use Absinthe.Schema.Notation

  object :price_point do
    field(:datetime, non_null(:datetime))
    field(:marketcap, :float)
    field(:price_usd, :float)
    field(:price_btc, :float)
    field(:volume, :float)
    field(:ticker, :string)
  end

  object :ohlcv do
    field(:price_points, list_of(:price_point))
    field(:open_price_usd, :float)
    field(:high_price_usd, :float)
    field(:low_price_usd, :float)
    field(:close_price_usd, :float)
    field(:open_price_btc, :float)
    field(:high_price_btc, :float)
    field(:low_price_btc, :float)
    field(:close_price_btc, :float)
  end
end
