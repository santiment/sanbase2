defmodule SanbaseWeb.Graphql.MarketTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  object :market_exchange do
    field(:exchange, non_null(:string))
    field(:assets_count, non_null(:integer))
    field(:pairs_count, non_null(:integer))
  end
end
