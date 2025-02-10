defmodule SanbaseWeb.Graphql.ExchangeTypes do
  @moduledoc false
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

  object :top_exchange_balance do
    field(:owner, non_null(:string))
    field(:label, non_null(:string))
    field(:balance, :float)
    field(:balance_change1d, :float)
    field(:balance_change7d, :float)
    field(:balance_change30d, :float)
    field(:datetime_of_first_transfer, :datetime)
    field(:days_since_first_transfer, :integer)
  end
end
