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

    @desc ~s"""
    Return the balance changes (amount and percent) for every address in the list.
    The returned result shows how the balance changed between the two dates.

    Example:

      Request:
      {
        addressHistoricalBalanceChange(
          addresses: ["0xa890499777eb045c6d0a380ce4d7262f91d200e1", "0x37480ca37666bc8584f2ed92361bdc71b1f4aade"]
          selector: {slug: "uniswap", infrastructure: "ETH"}
          from: "utc_now-7d"
          to: "utc_now") {
            address
            balanceStart
            balanceEnd
            balanceChangeAmount
            balanceChangePercent
        }
      }

      Result:
      {
      "data": {
        "addressHistoricalBalanceChange": [
          {
            "address": "0x37480ca37666bc8584f2ed92361bdc71b1f4aade",
            "balanceChangeAmount": 0,
            "balanceChangePercent": 0,
            "balanceEnd": 100,
            "balanceStart": 100
          },
          {
            "address": "0xa890499777eb045c6d0a380ce4d7262f91d200e1",
            "balanceChangeAmount": 0,
            "balanceChangePercent": 0,
            "balanceEnd": 0,
            "balanceStart": 0
          }
        ]
      }
    }
    """
    field :address_historical_balance_change, list_of(:address_balance_change) do
      meta(access: :free)

      arg(:selector, :historical_balance_selector)
      arg(:addresses, list_of(:string))
      arg(:from, non_null(:datetime))
      arg(:to, non_null(:datetime))

      complexity(&Complexity.from_to_interval/3)
      middleware(AccessControl)
      cache_resolve(&HistoricalBalanceResolver.address_historical_balance_change/3)
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
