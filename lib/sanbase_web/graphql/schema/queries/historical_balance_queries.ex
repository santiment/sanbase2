defmodule SanbaseWeb.Graphql.Schema.HistoricalBalanceQueries do
  use Absinthe.Schema.Notation

  import SanbaseWeb.Graphql.Cache, only: [cache_resolve: 1]

  alias SanbaseWeb.Graphql.Resolvers.HistoricalBalanceResolver

  alias SanbaseWeb.Graphql.Complexity
  alias SanbaseWeb.Graphql.Middlewares.AccessControl

  object :historical_balance_queries do
    @desc ~s"""
    Return a list of assets that a wallet currently holds.
    """
    field :assets_held_by_address, list_of(:slug_balance) do
      meta(access: :free)

      arg(:selector, :address_selector_input_object)
      arg(:address, :string)

      cache_resolve(&HistoricalBalanceResolver.assets_held_by_address/3)
    end

    @desc ~s"""
    Historical balance for erc20 token or eth address.
    Returns the historical balance for a given address in the given interval.
    """
    field :historical_balance, list_of(:historical_balance) do
      meta(access: :free)

      arg(:slug, :string)
      arg(:selector, :historical_balance_selector)
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:address, non_null(:string))
      arg(:interval, non_null(:interval), default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&HistoricalBalanceResolver.historical_balance/3)
    end

    @desc """
    Returns miner balances over time.
    Currently only ETH is supported.
    """
    field :miners_balance, list_of(:miners_balance) do
      meta(access: :restricted, min_plan: [sanapi: :pro, sanbase: :free])

      arg(:slug, :string, default_value: "ethereum")
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))
      arg(:interval, :interval, default_value: "1d")

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&HistoricalBalanceResolver.miners_balance/3)
    end
  end
end
