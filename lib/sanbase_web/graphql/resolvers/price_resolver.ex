defmodule SanbaseWeb.Graphql.PriceResolver do
  require Logger

  alias Sanbase.Prices.Store
  alias SanbaseWeb.Graphql.PriceTypes

  @doc """
  Returns a list of price points for the given ticker. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  def history_price(
        _root,
        %{ticker: ticker, from: from, to: to, interval: interval} = args,
        resolution
      ) do
        history_price(args, requested_fields(resolution))
  end

  def current_price(_root, %{ticker: ticker}, _resolution) do
    with {datetime, price_usd, marketcap, volume} <-
           Store.last_record(String.upcase(ticker) <> "_USD"),
         {_, price_btc, _, _} <- Store.last_record(String.upcase(ticker) <> "_BTC") do
      {:ok, %{
        datetime: datetime,
        price_btc: Decimal.new(price_btc),
        price_usd: Decimal.new(price_usd),
        marketcap: Decimal.new(marketcap),
        volume: Decimal.new(volume)
      }}
    else
      {:error, reason} ->
        {:error, "Cannot fetch price for ticker #{ticker}: #{reason}"}

      _ ->
        {:error, "Cannot fetch price for ticker #{ticker}"}
    end
  end

  def available_prices(_root, _args, _resolutions) do
    data = Store.list_measurements()
    |> Enum.map(&trim_measurement/1)
    |> Enum.reject(&is_nil/1)

    {:ok, data}
  end

  defp trim_measurement(name) do
    case String.ends_with?(name, "_BTC") do
      true -> String.slice(name, 0..-5)
      _ -> nil
    end
  end

  defp history_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceBtc: true,
         priceUsd: true
       }) do
    result_usd = String.upcase(ticker) <> "_USD" |> get_price_points(from, to, interval)
    result_btc = String.upcase(ticker) <> "_BTC" |> get_price_points(from, to, interval)

    # Zip the price in USD and BTC so they are shown as a single price point
    result =
      Enum.zip(result_btc, result_usd)
      |> Enum.map(fn {btc_map, %{price_usd: price_usd}} ->
           Map.put(btc_map, :price_usd, price_usd)
         end)

    {:ok, result}
  end

  defp history_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceBtc: true
       }) do
    result =
      (String.upcase(ticker) <> "_BTC")
      |> get_price_points(from, to, interval)

    {:ok, result}
  end

  defp history_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceUsd: true
       }) do
    result =
      (String.upcase(ticker) <> "_USD")
      |> get_price_points(from, to, interval)

    {:ok, result}
  end

  defp history_price(args, fields) do
    Logger.warn("Unexpected arguments passed to history_price")
  end

  defp requested_fields(context) do
    context.definition.selections
    |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
    |> Enum.into(%{}, fn field -> {field, true} end)
  end

  # Set the same price for BTC and USD. Function is only used when zipping the time series
  # where the right price is set as appropriate
  defp to_price_point([datetime, price, volume, marketcap]) do
    %{
      datetime: datetime,
      price_btc: Decimal.new(price),
      price_usd: Decimal.new(price),
      marketcap: Decimal.new(marketcap),
      volume: Decimal.new(volume)
    }
  end

  defp get_price_points(pair, from, to, interval) do
    Store.fetch_prices_with_resolution(
      pair,
      from,
      to,
      interval
    )
    |> Enum.map(&to_price_point/1)
  end
end