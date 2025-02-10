defmodule SanbaseWeb.Graphql.PriceTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :price_point do
    field(:datetime, non_null(:datetime))
    field(:marketcap, :float)
    field(:marketcap_usd, :float)
    field(:price_usd, :float)
    field(:price_btc, :float)
    field(:volume, :float)
    field(:volume_usd, :float)
    field(:ticker, :string, deprecate: "No longer supported")
  end

  object :ohlc do
    field(:datetime, non_null(:datetime))
    field(:open_price_usd, :float)
    field(:high_price_usd, :float)
    field(:low_price_usd, :float)
    field(:close_price_usd, :float)
  end

  object :project_stats do
    field(:slug, :string)
    field(:volume, :float)
    field(:volume_usd, :float)
    field(:marketcap, :float)
    field(:marketcap_usd, :float)
    field(:marketcap_percent, :float)
  end

  object :combined_projects_stats do
    field(:datetime, non_null(:datetime))
    field(:volume, :float)
    field(:volume_usd, :float)
    field(:marketcap, :float)
    field(:marketcap_usd, :float)
  end
end
