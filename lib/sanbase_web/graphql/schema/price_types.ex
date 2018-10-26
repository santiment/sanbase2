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

  object :ohlc do
    field(:datetime, non_null(:datetime))
    field(:open_price_usd, :float)
    field(:high_price_usd, :float)
    field(:low_price_usd, :float)
    field(:close_price_usd, :float)
  end

  object :group_stats do
    field(:volume, :float)
    field(:marketcap, :float)
    field(:marketcap_percent, list_of(:slug_mcap))
  end

  object :slug_mcap do
    field(:slug, :string)
    field(:percent, :float)
  end
end
