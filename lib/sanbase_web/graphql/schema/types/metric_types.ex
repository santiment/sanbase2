defmodule SanbaseWeb.Graphql.MetricTypes do
  use Absinthe.Schema.Notation

  object :metric do
    field(:datetime, non_null(:datetime))
    field(:value, non_null(:float))
  end

  enum :aggregation do
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
