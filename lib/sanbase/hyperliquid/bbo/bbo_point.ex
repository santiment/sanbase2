defmodule Sanbase.Hyperliquid.Bbo.BboPoint do
  @derive Jason.Encoder
  defstruct [
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

  @doc ~s"""
  Parse the payload of a `bbo` frame (`data.coin`/`data.time`/`data.bbo`
  sides) into the slug-less field map used to build one `#{inspect(__MODULE__)}`
  per mapped slug. Returns nil when both sides are empty (nothing to export)
  — one-sided books are kept, with the missing side's fields nil.
  """
  def parse_frame_data(coin, time_ms, bid, ask) do
    {bp, bv} = parse_side(bid)
    {ap, av} = parse_side(ask)

    if Enum.all?([bp, bv, ap, av], &is_nil/1) do
      nil
    else
      %{
        coin: coin,
        timestamp_ms: time_ms,
        bid_price: bp,
        bid_volume: bv,
        ask_price: ap,
        ask_volume: av
      }
    end
  end

  defp parse_side(%{"px" => px, "sz" => sz}) do
    {parse_float(px), parse_float(sz)}
  end

  defp parse_side(_), do: {nil, nil}

  defp parse_float(n) when is_number(n), do: n * 1.0

  defp parse_float(s) when is_binary(s) do
    case Float.parse(s) do
      {f, _} -> f
      :error -> nil
    end
  end

  defp parse_float(_), do: nil
end
