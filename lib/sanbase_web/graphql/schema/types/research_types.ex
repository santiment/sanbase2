defmodule SanbaseWeb.Graphql.ResearchTypes do
  use Absinthe.Schema.Notation

  object :uniswap_value_distribution do
    field(:total_minted, :float)
    field(:centralized_exchanges, :float)
    field(:decentralized_exchanges, :float)
    field(:cex_trader, :float)
    field(:dex_trader, :float)
    field(:cex_dex_trader, :float)
    field(:other_transfers, :float)
  end

  object :uniswap_who_claimed do
    field(:cex_trader, :float)
    field(:centralized_exchanges, :float)
    field(:decentralized_exchanges, :float)
    field(:other_addresses, :float)
  end
end
