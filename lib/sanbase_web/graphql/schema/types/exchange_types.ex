defmodule SanbaseWeb.Graphql.ExchangeTypes do
  use Absinthe.Schema.Notation

  object :slug_pair do
    field(:from_slug, :string)
    field(:to_slug, :string)
  end

  object :market_pair do
    field(:market_pair, :string)
    field(:from_ticker, :string)
    field(:to_ticker, :string)
  end
end
