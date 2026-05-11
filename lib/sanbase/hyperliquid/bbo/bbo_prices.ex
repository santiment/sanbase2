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

    ClickhouseRepo.query_transform(query_struct, fn
      [time, bid_price, bid_volume, ask_price, ask_volume] ->
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

  defp mid_price(bid, ask) do
    if Enum.all?([bid, ask], &is_number/1), do: (bid + ask) / 2
  end

  defp weighted_mid_price(bid_p, bid_v, ask_p, ask_v) do
    if Enum.all?([bid_p, bid_v, ask_p, ask_v], &is_number/1) and bid_v + ask_v != 0 do
      (bid_p * ask_v + ask_p * bid_v) / (bid_v + ask_v)
    end
  end
end
