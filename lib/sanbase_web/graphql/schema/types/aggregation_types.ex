defmodule SanbaseWeb.Graphql.AggregationTypes do
  @moduledoc false
  use Absinthe.Schema.Notation

  enum :aggregation do
    value(:none)
    value(:count)
    value(:any)
    value(:last)
    value(:first)
    value(:avg)
    value(:sum)
    value(:min)
    value(:max)
    value(:median)
    value(:ohlc)
  end
end
