defmodule Sanbase.Prices.Utils do
  alias Sanbase.Prices.Store

  @bitcoin_measurement "BTC_bitcoin"
  @ethereum_measurement "ETH_ethereum"

  defguard is_zero(price)
           when is_number(price) and price >= -1.0e-7 and price <= 1.0e-7

  @spec fetch_last_price_before(String.t(), Integer) :: {number(), number()} | {nil, nil}
  def fetch_last_price_before(measurement, timestamp) do
    Store.fetch_last_price_point_before(measurement, timestamp)
    |> case do
      {:ok, [[_, price_usd, price_btc, _, _]]} ->
        {price_usd, price_btc}

      _ ->
        {nil, nil}
    end
  end

  @doc """
    Converts prices between currencies. Tries intermediate conversions with USD/BTC
    if data for direct conversion is not available.
  """
  def fetch_last_price_before(measurement, measurement, _timestamp), do: 1.0

  def fetch_last_price_before(currency, "USD", timestamp)
      when currency in ["BTC", @bitcoin_measurement] do
    {price_usd, _price_btc} = fetch_last_price_before(@bitcoin_measurement, timestamp)
    price_usd
  end

  def fetch_last_price_before(currency, "USD", timestamp)
      when currency in ["ETH", @ethereum_measurement] do
    {price_usd, _price_btc} = fetch_last_price_before(@ethereum_measurement, timestamp)
    price_usd
  end

  def fetch_last_price_before("USD", "BTC", timestamp) do
    {_price_usd, price_btc} = fetch_last_price_before(@bitcoin_measurement, timestamp)

    case price_btc do
      x when is_nil(x) or is_zero(x) -> nil
      price -> 1 / price
    end
  end

  @doc ~s"""
    We need the next 4 cases when calling from `convert_amount`. There we get
    a currency code (a ticker that has to be unique) and we get the project from that
    code so we can construct the `ticker_coinmarketcap_id` measurement name.
  """
  def fetch_last_price_before(measurement, "USD", timestamp) do
    {price_usd, _price_btc} = fetch_last_price_before(measurement, timestamp)

    case price_usd do
      nil -> fetch_last_price_usd_before_convert_via_btc(measurement, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(measurement, "BTC", timestamp) do
    {_price_usd, price_btc} = fetch_last_price_before(measurement, timestamp)

    case price_btc do
      nil -> fetch_last_price_btc_before_convert_via_usd(measurement, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(measurement, "ETH", timestamp) do
    fetch_last_price_before_convert_via_intermediate(
      measurement,
      @ethereum_measurement,
      "USD",
      timestamp
    )
  end

  def fetch_last_price_before(measurement_from, measurement_to, timestamp)
      when measurement_to != "USD" and measurement_to != "BTC" do
    price =
      fetch_last_price_before_convert_via_intermediate(
        measurement_from,
        measurement_to,
        "USD",
        timestamp
      )

    case price do
      nil ->
        fetch_last_price_before_convert_via_intermediate(
          measurement_from,
          measurement_to,
          "BTC",
          timestamp
        )

      price ->
        price
    end
  end

  # Private functions

  defp fetch_last_price_before_convert_via_intermediate(
         measurement_from,
         measurement_to,
         measurement_interm,
         timestamp
       ) do
    with price_from_interm <-
           fetch_last_price_before(measurement_from, measurement_interm, timestamp),
         false <- is_nil(price_from_interm) or is_zero(price_from_interm),
         price_to_interm <-
           fetch_last_price_before(measurement_to, measurement_interm, timestamp),
         false <- is_nil(price_to_interm) or is_zero(price_to_interm) do
      price_from_interm / price_to_interm
    else
      _ -> nil
    end
  end

  defp fetch_last_price_usd_before_convert_via_btc(measurement, timestamp) do
    with {_price_usd, price_btc} <- fetch_last_price_before(measurement, timestamp),
         false <- is_nil(price_btc),
         {price_btc_usd, _price_btc_btc} <-
           fetch_last_price_before(@bitcoin_measurement, timestamp),
         false <- is_nil(price_btc_usd) do
      price_btc * price_btc_usd
    else
      _ -> nil
    end
  end

  defp fetch_last_price_btc_before_convert_via_usd(measurement, timestamp) do
    with {price_usd, _price_btc} <- fetch_last_price_before(measurement, timestamp),
         false <- is_nil(price_usd) or is_zero(price_usd),
         {price_btc_usd, _price_btc_btc} <-
           fetch_last_price_before(@bitcoin_measurement, timestamp),
         false <- is_nil(price_btc_usd) or is_zero(price_btc_usd) do
      price_usd / price_btc_usd
    else
      _ -> nil
    end
  end

  def convert_amount(nil, _currency_from, _measurement_to, _timestamp), do: nil

  def convert_amount(amount, currency, currency, _timestamp) do
    Decimal.to_float(amount)
  end

  def convert_amount(
        amount,
        currency_from,
        target_currency,
        timestamp
      ) do
    alias Sanbase.Model.{Project, Currency}

    %Project{ticker: ticker, coinmarketcap_id: cmc_id} =
      Currency.to_project(%Currency{code: currency_from})

    ticker_cmc_id = ticker <> "_" <> cmc_id

    fetch_last_price_before(ticker_cmc_id, target_currency, timestamp)
    |> case do
      nil ->
        nil

      price ->
        price * Decimal.to_float(amount)
    end
  end
end
