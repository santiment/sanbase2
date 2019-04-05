defmodule SanbaseWeb.Graphql.ClickhouseTypes do
  use Absinthe.Schema.Notation

  object :active_addresses do
    field(:datetime, non_null(:datetime))
    field(:active_addresses, non_null(:integer))
  end

  object :active_deposits do
    field(:datetime, non_null(:datetime))
    field(:active_deposits, non_null(:integer))
  end

  object :gas_used do
    field(:datetime, non_null(:datetime))
    field(:eth_gas_used, :integer)
  end

  object :historical_balance do
    field(:datetime, non_null(:datetime))
    field(:balance, :float)
  end

  object :mining_pools_distribution do
    field(:datetime, non_null(:datetime))
    field(:top3, :float)
    field(:top10, :float)
    field(:other, :float)
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

  object :realized_value do
    field(:datetime, non_null(:datetime))
    field(:realized_value, :integer)
    field(:non_exchange_realized_value, :integer)
  end
end
