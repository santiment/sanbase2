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
    only: [
      timeseries_data_query: 4,
      first_datetime_query: 1,
      last_datetime_computed_at_query: 1
    ]

  import Sanbase.Utils.Transform, only: [maybe_unwrap_ok_value: 1]

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

  @doc ~s"""
  Return `weighted_mid_price` as a `%{datetime: _, value: _}` timeseries - the
  `price_usd` metric for the `hyperliquid` source. Buckets where the value
  cannot be computed carry a nil value, as for every other metric.
  """
  @spec price_usd_timeseries_data(String.t(), DateTime.t(), DateTime.t(), String.t()) ::
          {:ok, [%{datetime: DateTime.t(), value: float() | nil}]} | {:error, String.t()}
  def price_usd_timeseries_data(slug, from, to, interval) do
    with {:ok, data} <- timeseries_data(slug, from, to, interval) do
      {:ok, Enum.map(data, &%{datetime: &1.datetime, value: &1.weighted_mid_price})}
    end
  end

  @doc ~s"""
  Return the datetime of the oldest BBO record for `slug`.
  """
  @spec first_datetime(String.t()) :: {:ok, DateTime.t()} | {:error, String.t()}
  def first_datetime(slug) do
    first_datetime_query(slug)
    |> ClickhouseRepo.query_transform(fn [timestamp] -> DateTime.from_unix!(timestamp) end)
    |> maybe_unwrap_ok_value()
  end

  @doc ~s"""
  Return the datetime of the newest BBO record for `slug`.
  """
  @spec last_datetime_computed_at(String.t()) :: {:ok, DateTime.t()} | {:error, String.t()}
  def last_datetime_computed_at(slug) do
    last_datetime_computed_at_query(slug)
    |> ClickhouseRepo.query_transform(fn [timestamp] -> DateTime.from_unix!(timestamp) end)
    |> maybe_unwrap_ok_value()
  end

  # Hyperliquid quotes some low-priced assets per 1000 underlying tokens, signalled only by
  # a lowercase "k" prefix on the coin name ("kPEPE", "kSHIB", ...): `px` is USD per 1000
  # tokens and `sz` a number of 1000-token contracts. Native-token units preserving notional
  # (`price * volume`) therefore divide price by 1000 and multiply volume by 1000.
  #
  # The convention is NOT documented and `POST /info {"type":"meta"}` exposes no
  # price/size multiplier - only `name`, `szDecimals`, `maxLeverage`, `marginTableId`,
  # `marginMode`. Verified against `POST /info {"type":"l2Book","coin":"kPEPE"}`:
  # `px=0.003691` with `sz=202527` is a notional of ~$748, realistic only if `px` is per
  # 1000 PEPE and `sz` is in contracts. Matching the prefix beats a hardcoded list that
  # goes stale as Hyperliquid adds k-assets.
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
