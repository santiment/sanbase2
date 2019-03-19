defmodule SanbaseWeb.Graphql.ClickhouseTypes do
  use Absinthe.Schema.Notation

  object :active_deposits do
    field(:datetime, non_null(:datetime))
    field(:active_deposits, non_null(:integer))
  end

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end

  object :mvrv_ratio do
    field(:datetime, non_null(:datetime))
    field(:ratio, :float)
  end

  object :network_growth do
    field(:datetime, non_null(:datetime))
    field(:new_addresses, :integer)
  end

  object :nvt_ratio do
    field(:datetime, non_null(:datetime))
    field(:nvt_ratio_circulation, :float)
    field(:nvt_ratio_tx_volume, :float)
  end
end
