defmodule Sanbase.Hyperliquid.Bbo.BboPrices do
  @moduledoc ~s"""
  Read-side API for the `hyperliquid_bbo_prices` ClickHouse table.

  Returns bucketed timeseries: for each bucket of width `interval`, bid/ask
  values are taken from the row with the largest `dt` (tuple `argMax`), so
  every output row reflects a single source snapshot.

  Per row we expose `mid_price` (`(bid + ask) / 2`) and `weighted_mid_price`
  (`(bid_price * ask_volume + ask_price * bid_volume) / (bid_volume + ask_volume)`).
  Both are nil when either side of the book is missing; `weighted_mid_price`
  is also nil when the volume denominator is 0.
  """

  import Sanbase.Hyperliquid.Bbo.BboSqlQuery,
    only: [timeseries_data_query: 4]

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Project.SourceSlugMapping

  @source "hyperliquid"

  @type point :: %{
          datetime: DateTime.t(),
          bid_price: float() | nil,
          bid_volume: float() | nil,
          ask_price: float() | nil,
          ask_volume: float() | nil,
          mid_price: float() | nil,
          weighted_mid_price: float() | nil
        }

  @doc ~s"""
  Return BBO timeseries for `slug` between `from` and `to`, bucketed by
  `interval`. Each bucket carries the bid/ask snapshot from the row with the
  largest `dt` in the bucket, plus computed `mid_price` and
  `weighted_mid_price` (nil when either side is missing; weighted is also nil
  when bid_volume + ask_volume = 0).

  `interval` accepts `"1m"`, `"5m"`, `"1h"`, etc. — anything
  `Sanbase.Utils.DateTime.maybe_str_to_sec/1` understands.
  """
  @spec timeseries_data(String.t(), DateTime.t(), DateTime.t(), String.t()) ::
          {:ok, [point]} | {:error, String.t()}
  def timeseries_data(slug, from, to, interval) do
    query_struct = timeseries_data_query(slug, from, to, interval)
    k_factor = k_factor(slug)

    ClickhouseRepo.query_transform(query_struct, fn
      [time, bid_price, bid_volume, ask_price, ask_volume] ->
        bid_price = scale_price(bid_price, k_factor)
        bid_volume = scale_volume(bid_volume, k_factor)
        ask_price = scale_price(ask_price, k_factor)
        ask_volume = scale_volume(ask_volume, k_factor)

        %{
          datetime: DateTime.from_unix!(time),
          bid_price: bid_price,
          bid_volume: bid_volume,
          ask_price: ask_price,
          ask_volume: ask_volume,
          mid_price: mid_price(bid_price, ask_price),
          weighted_mid_price: weighted_mid_price(bid_price, bid_volume, ask_price, ask_volume)
        }
    end)
  end

  # Hyperliquid quotes some low-priced assets per 1000 underlying tokens. The
  # only signal is a lowercase "k" prefix on the coin name (e.g. "kPEPE",
  # "kSHIB", "kBONK", "kLUNC", "kFLOKI"); the convention is "k" for kilo, so
  # one quoted contract represents 1000 of the underlying. Raw fields from
  # Hyperliquid are therefore:
  #
  #   * `px` — USD per 1000 underlying tokens
  #   * `sz` — number of contracts (each = 1000 underlying tokens)
  #
  # To expose values in native-token units while preserving notional
  # (`price * volume`), price is divided by 1000 and volume is multiplied by
  # 1000 for k-prefixed coins.
  #
  # This convention is NOT formally documented in the Hyperliquid docs
  # (perpetuals info endpoint, tick/lot size, contract specifications). The
  # live `POST /info {"type":"meta"}` response exposes `name`, `szDecimals`,
  # `maxLeverage`, `marginTableId`, `marginMode` per asset — none of which is
  # a price/size multiplier. The encoding was verified empirically against
  # `POST /info {"type":"l2Book","coin":"kPEPE"}`: a quoted `px=0.003691` with
  # `sz=202527` gives notional `0.003691 * 202527 ≈ $748`, which only matches
  # realistic order sizes if `px` is per 1000 PEPE and `sz` is in contracts.
  # Matching on the name prefix is the only option short of hardcoding a list,
  # which would go stale as Hyperliquid adds new k-assets.
  defp k_factor(sanbase_slug) do
    case SourceSlugMapping.get_source_slug(sanbase_slug, @source) do
      "k" <> _ -> 1000
      _ -> 1
    end
  end

  defp scale_price(nil, _factor), do: nil
  defp scale_price(value, factor), do: value / factor

  defp scale_volume(nil, _factor), do: nil
  defp scale_volume(value, factor), do: value * factor

  defp mid_price(bid, ask) do
    if Enum.all?([bid, ask], &is_number/1), do: (bid + ask) / 2
  end

  defp weighted_mid_price(bid_p, bid_v, ask_p, ask_v) do
    if Enum.all?([bid_p, bid_v, ask_p, ask_v], &is_number/1) and bid_v + ask_v != 0 do
      (bid_p * ask_v + ask_p * bid_v) / (bid_v + ask_v)
    end
  end
end
