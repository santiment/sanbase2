defmodule SanbaseWeb.Graphql.ClickhouseTypes do
  use Absinthe.Schema.Notation

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end

  object :network_growth do
    field(:datetime, non_null(:datetime))
    field(:new_addresses, :integer)
  end

  object :mvrv_ratio do
    field(:datetime, non_null(:datetime))
    field(:ratio, :float)
  end
end
