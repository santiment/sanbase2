defmodule SanbaseWeb.Graphql.HyperliquidTypes do
  use Absinthe.Schema.Notation

  @desc ~s"""
  A bucketed BBO (best bid / best offer) snapshot for a Hyperliquid asset.

  Within each interval bucket we return the values from the row with the
  largest `dt` (atomic snapshot — bid and ask always come from the same row).

  `mid_price` and `weighted_mid_price` are null whenever either side of the
  book is missing.
  """
  object :hyperliquid_bbo_point do
    field(:datetime, non_null(:datetime))
    field(:bid_price, :float)
    field(:bid_volume, :float)
    field(:ask_price, :float)
    field(:ask_volume, :float)

    @desc "Arithmetic mid: (bid_price + ask_price) / 2."
    field(:mid_price, :float)

    @desc ~s"""
    Volume-weighted mid:
    (bid_price * ask_volume + ask_price * bid_volume) / (bid_volume + ask_volume).
    """
    field(:weighted_mid_price, :float)
  end
end
