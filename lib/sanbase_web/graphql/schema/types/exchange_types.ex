defmodule SanbaseWeb.Graphql.ExchangeTypes do
  use Absinthe.Schema.Notation

  object :exchange_volume do
    field(:datetime, non_null(:datetime))
    field(:exchange_inflow, :float)
    field(:exchange_outflow, :float)
  end

  object :slug_pair do
    field(:from_slug, :string)
    field(:to_slug, :string)
  end
end
