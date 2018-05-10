defmodule Sanbase.Prices.Utils do
  alias Sanbase.Prices.Store

  @bitcoin_measurement "BTC_bitcoin"
  @ethereum_measurement "ETH_ethereum"

  def fetch_last_price_before(pair, timestamp) do
    Store.fetch_last_price_point_before(pair, timestamp)
    |> case do
      {:ok, [[_, price_usd, price_btc, _, _]]} ->
        {Decimal.new(price_usd), Decimal.new(price_btc)}

      _ ->
        {nil, nil}
    end
  end

  @doc """
  Converts prices between currencies. Tries intermediate conversions with USD/BTC
  if data for direct conversion is not available.
  """
  def fetch_last_price_before(ticker, ticker, _timestamp), do: Decimal.new(1)

  def fetch_last_price_before("BTC", "USD", timestamp) do
    {price_usd, _price_btc} = fetch_last_price_before(@bitcoin_measurement, timestamp)
    price_usd
  end

  defguard is_zero(price)
           when is_float(price) and not (0.0 > price) and price <= 1.0e-7

  def fetch_last_price_before("USD", "BTC", timestamp) do
    zero = Decimal.new(0)
    {_price_usd, price_btc} = fetch_last_price_before(@bitcoin_measurement, timestamp)

    case price_btc do
      nil -> nil
      x when is_zero(x) -> nil
      price -> Decimal.div(Decimal.new(1), price)
    end
  end

  def fetch_last_price_before(measurement, "USD", timestamp) do
    {price_usd, _price_btc} = fetch_last_price_before(measurement, timestamp)

    case price_usd do
      nil -> fetch_last_price_usd_before_convert_via_btc(measurement, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(measurement, "BTC", timestamp) do
    fetch_last_price_before(measurement, timestamp)
    |> case do
      nil -> fetch_last_price_btc_before_convert_via_usd(measurement, timestamp)
      price -> price
    end
  end

  # Private functions

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

  def convert_amount(nil, _measurement_from, _measurement_to, _timestamp), do: nil

  def convert_amount(amount, measurement_from, measurement_to, timestamp) do
    fetch_last_price_before(measurement_from, measurement_to, timestamp)
    |> case do
      nil -> nil
      price -> Decimal.mult(price, amount)
    end
  end
end
