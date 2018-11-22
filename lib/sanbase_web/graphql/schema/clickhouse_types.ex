defmodule SanbaseWeb.Graphql.ClickhouseTypes do
  use Absinthe.Schema.Notation

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end
end
