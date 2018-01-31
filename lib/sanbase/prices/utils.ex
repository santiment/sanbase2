defmodule Sanbase.Prices.Utils do
  alias Sanbase.Prices.Store

  def fetch_last_price_before(pair, timestamp) do
    Store.fetch_last_price_point_before(pair, timestamp)
    |> case do
      {_, nil, _, _} -> nil
      {_, price, _, _} -> Decimal.new(price)
      _ -> nil
    end
  end

  @doc """
  Converts prices between currencies. Tries intermediate conversions with USD/BTC
  if data for direct conversion is not available.
  """
  def fetch_last_price_before(ticker, ticker, _timestamp), do: Decimal.new(1)

  def fetch_last_price_before("BTC", "USD", timestamp) do
    fetch_last_price_before("BTC_USD", timestamp)
  end

  def fetch_last_price_before("USD", "BTC", timestamp) do
    zero = Decimal.new(0)

    fetch_last_price_before("BTC_USD", timestamp)
    |> case do
      nil -> nil
      ^zero -> nil
      price -> Decimal.div(Decimal.new(1), price)
    end
  end

  def fetch_last_price_before(ticker_from, "USD", timestamp) do
    fetch_last_price_before(ticker_from <> "_USD", timestamp)
    |> case do
      nil -> fetch_last_price_usd_before_convert_via_btc(ticker_from, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(ticker_from, "BTC", timestamp) do
    fetch_last_price_before(ticker_from <> "_BTC", timestamp)
    |> case do
      nil -> fetch_last_price_btc_before_convert_via_usd(ticker_from, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(ticker_from, ticker_to, timestamp)
      when ticker_to != "USD" and ticker_to != "BTC" do
    fetch_last_price_before_convert_via_intermediate(ticker_from, ticker_to, "USD", timestamp)
    |> case do
      nil ->
        fetch_last_price_before_convert_via_intermediate(ticker_from, ticker_to, "BTC", timestamp)

      price ->
        price
    end
  end

  defp fetch_last_price_usd_before_convert_via_btc(ticker_from, timestamp) do
    with price_btc <- fetch_last_price_before(ticker_from <> "_BTC", timestamp),
         true <- !is_nil(price_btc),
         price_btc_usd <- fetch_last_price_before("BTC_USD", timestamp),
         true <- !is_nil(price_btc_usd) do
      Decimal.mult(price_btc, price_btc_usd)
    else
      _ -> nil
    end
  end

  defp fetch_last_price_btc_before_convert_via_usd(ticker_from, timestamp) do
    with price_usd <- fetch_last_price_before(ticker_from <> "_USD", timestamp),
         true <- !is_nil(price_usd),
         price_btc_usd <- fetch_last_price_before("BTC_USD", timestamp),
         true <- !is_nil(price_btc_usd) and price_btc_usd != Decimal.new(0) do
      Decimal.div(price_usd, price_btc_usd)
    else
      _ -> nil
    end
  end

  defp fetch_last_price_before_convert_via_intermediate(
         ticker_from,
         ticker_to,
         ticker_interm,
         timestamp
       ) do
    with price_from_interm <- fetch_last_price_before(ticker_from, ticker_interm, timestamp),
         true <- !is_nil(price_from_interm),
         price_to_interm <- fetch_last_price_before(ticker_to, ticker_interm, timestamp),
         true <- !is_nil(price_to_interm) and price_to_interm != Decimal.new(0) do
      Decimal.div(price_from_interm, price_to_interm)
    else
      _ -> nil
    end
  end

  def convert_amount(nil, _ticker_from, _ticker_to, _timestamp), do: nil

  def convert_amount(amount, ticker_from, ticker_to, timestamp) do
    fetch_last_price_before(ticker_from, ticker_to, timestamp)
    |> case do
      nil -> nil
      price -> Decimal.mult(price, amount)
    end
  end
end
