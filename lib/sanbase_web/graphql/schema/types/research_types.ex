defmodule SanbaseWeb.Graphql.ResearchTypes do
  use Absinthe.Schema.Notation

  object :uniswap_value_distribution do
    field(:total_minted, :float)
    field(:centralized_exchanges, :float)
    field(:decentralized_exchanges, :float)
    field(:other_transfers, :float)
    field(:dex_trader, :float)
  end
end
