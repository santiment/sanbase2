defmodule SanbaseWeb.Graphql.Schema.HyperliquidQueries do
  use Absinthe.Schema.Notation

  object :hyperliquid_queries do
    @desc ~s"""
    Entry point for Hyperliquid BBO (best bid / best offer) data.

    Returns an object with sub-fields:
      * `timeseriesData` — bucketed BBO timeseries for a given slug.
      * `availableProjects` — projects that have a `hyperliquid` source mapping.
    """
    field :hyperliquid_bbo_prices, :hyperliquid_bbo_data do
      meta(access: :free)

      resolve(fn _root, _args, _resolution -> {:ok, %{__source__: :hyperliquid_bbo_prices}} end)
    end
  end
end
