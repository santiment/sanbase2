defmodule SanbaseWeb.Graphql.ClickhouseTypes do
  use Absinthe.Schema.Notation

  object :fees_distribution do
    field(:slug, :string)
    field(:ticker, :string)
    field(:address, :string)
    field(:project, :project)
    field(:fees, non_null(:float))
  end

  object :active_addresses do
    field(:datetime, non_null(:datetime))
    field(:active_addresses, non_null(:float))
  end

  object :active_deposits do
    field(:datetime, non_null(:datetime))
    field(:active_deposits, non_null(:float))
  end

  object :gas_used do
    field(:datetime, non_null(:datetime))
    field(:eth_gas_used, :float, deprecate: "Use gasUsed")
    field(:gas_used, :float)
  end

  object :mvrv_ratio do
    field(:datetime, non_null(:datetime))
    field(:ratio, :float)
  end

  object :network_growth do
    field(:datetime, non_null(:datetime))
    field(:new_addresses, :float)
  end

  object :nvt_ratio do
    field(:datetime, non_null(:datetime))
    field(:nvt_ratio_circulation, :float)
    field(:nvt_ratio_tx_volume, :float)
  end

  object :realized_value do
    field(:datetime, non_null(:datetime))
    field(:realized_value, :float)
  end

  object :percent_of_token_supply_on_exchanges do
    field(:datetime, non_null(:datetime))
    field(:percent_on_exchanges, :float)
  end

  object :top_holders do
    field(:datetime, non_null(:datetime))
    field(:address, :string)
    field(:value, :float)
    field(:value_usd, :float)
    field(:labels, list_of(:label), default_value: [])
    field(:part_of_total, :float)
  end

  object :top_holders_percent_of_total_supply do
    field(:datetime, non_null(:datetime))
    field(:in_exchanges, :float)
    field(:outside_exchanges, :float)
    field(:in_top_holders_total, :float)
  end
end
