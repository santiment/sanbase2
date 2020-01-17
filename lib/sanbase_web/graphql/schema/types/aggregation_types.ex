defmodule SanbaseWeb.Graphql.AggregationTypes do
  use Absinthe.Schema.Notation

  enum :aggregation do
    value(:count)
    value(:any)
    value(:last)
    value(:first)
    value(:avg)
    value(:sum)
    value(:min)
    value(:max)
    value(:median)
  end
end
