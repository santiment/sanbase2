defmodule Sanbase.Hyperliquid.Bbo.BboPoint do
  @derive Jason.Encoder
  defstruct [
    :source,
    :slug,
    :coin,
    :timestamp_ms,
    :bid_price,
    :bid_volume,
    :ask_price,
    :ask_volume
  ]

  # bid_price/bid_volume are both set or both nil (one-sided book — no resting bid).
  # Same for ask_price/ask_volume. At least one side is always present.
  @type t :: %__MODULE__{
          source: String.t(),
          slug: String.t(),
          coin: String.t(),
          timestamp_ms: non_neg_integer(),
          bid_price: float() | nil,
          bid_volume: float() | nil,
          ask_price: float() | nil,
          ask_volume: float() | nil
        }

  def json_kv_tuple(%__MODULE__{} = point) do
    key = "hyperliquid_bbo_#{point.slug}_#{point.timestamp_ms}"
    {key, Jason.encode!(point)}
  end
end
