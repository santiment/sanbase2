defmodule Sanbase.Price.Utils do
  @moduledoc false
  import Sanbase.DateTimeUtils, only: [round_datetime: 1]

  defguard is_zero(price)
           when is_number(price) and price >= -1.0e-7 and price <= 1.0e-7

  @spec fetch_last_prices_before(String.t(), DateTime.t()) ::
          {number() | nil, number() | nil}
  def fetch_last_prices_before(slug, datetime) do
    cache_key = Sanbase.Cache.hash({__MODULE__, :last_record_before, slug, round_datetime(datetime)})

    last_record =
      Sanbase.Cache.get_or_store(cache_key, fn ->
        Sanbase.Price.last_record_before(slug, datetime)
      end)

    case last_record do
      {:ok, %{price_usd: price_usd, price_btc: price_btc}} ->
        {price_usd, price_btc}

      _ ->
        {nil, nil}
    end
  end

  @doc """
  Converts prices between currencies. Tries intermediate conversions with USD/BTC
  if data for direct conversion is not available.
  """
  def fetch_last_price_before(slug, slug, _timestamp), do: 1.0

  def fetch_last_price_before(currency, "USD", timestamp) when currency in ["BTC", "bitcoin"] do
    {price_usd, _price_btc} = fetch_last_prices_before("bitcoin", timestamp)
    price_usd
  end

  def fetch_last_price_before(currency, "USD", timestamp) when currency in ["ETH", "ethereum"] do
    {price_usd, _price_btc} = fetch_last_prices_before("ethereum", timestamp)
    price_usd
  end

  def fetch_last_price_before(currency, "BTC", timestamp) when currency in ["ETH", "ethereum"] do
    {_price_usd, price_btc} = fetch_last_prices_before("ethereum", timestamp)
    price_btc
  end

  def fetch_last_price_before("USD", "BTC", timestamp) do
    {_price_usd, price_btc} = fetch_last_prices_before("bitcoin", timestamp)

    case price_btc do
      x when is_nil(x) or is_zero(x) -> nil
      price -> 1 / price
    end
  end

  # We need the next 4 cases when calling from `convert_amount`. There we get
  # a currency code (a ticker that has to be unique) and we get the project from that
  # code so we can construct the `ticker_slug` slug name.
  def fetch_last_price_before(slug, "USD", timestamp) do
    {price_usd, _price_btc} = fetch_last_prices_before(slug, timestamp)

    case price_usd do
      nil -> fetch_last_price_usd_before_convert_via_btc(slug, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(slug, "BTC", timestamp) do
    {_price_usd, price_btc} = fetch_last_prices_before(slug, timestamp)

    case price_btc do
      nil -> fetch_last_price_btc_before_convert_via_usd(slug, timestamp)
      price -> price
    end
  end

  def fetch_last_price_before(slug, "ETH", timestamp) do
    fetch_last_price_before_convert_via_intermediate(
      slug,
      "ethereum",
      "USD",
      timestamp
    )
  end

  # Private functions

  defp fetch_last_price_before_convert_via_intermediate(slug_from, slug_to, slug_interm, timestamp) do
    price_from_interm =
      fetch_last_price_before(slug_from, slug_interm, timestamp)

    with false <- is_nil(price_from_interm) or is_zero(price_from_interm),
         price_to_interm =
           fetch_last_price_before(slug_to, slug_interm, timestamp),
         false <- is_nil(price_to_interm) or is_zero(price_to_interm) do
      price_from_interm / price_to_interm
    else
      _ -> nil
    end
  end

  defp fetch_last_price_usd_before_convert_via_btc(slug, timestamp) do
    with {_price_usd, price_btc} <- fetch_last_prices_before(slug, timestamp),
         false <- is_nil(price_btc),
         {price_btc_usd, _price_btc_btc} <- fetch_last_prices_before("bitcoin", timestamp),
         false <- is_nil(price_btc_usd) do
      price_btc * price_btc_usd
    else
      _ -> nil
    end
  end

  defp fetch_last_price_btc_before_convert_via_usd(slug, timestamp) do
    with {price_usd, _price_btc} <- fetch_last_prices_before(slug, timestamp),
         false <- is_nil(price_usd) or is_zero(price_usd),
         {price_btc_usd, _price_btc_btc} <-
           fetch_last_prices_before("bitcoin", timestamp),
         false <- is_nil(price_btc_usd) or is_zero(price_btc_usd) do
      price_usd / price_btc_usd
    else
      _ -> nil
    end
  end
end
