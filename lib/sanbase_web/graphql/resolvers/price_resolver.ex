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
        context
      ) do
    hist_price(args, requested_fields(context))
  end

  def current_price(_root, %{ticker: ticker}, _context) do
    with {datetime, price_usd, marketcap, volume} <-
           Store.last_record(String.upcase(ticker) <> "_USD"),
         {_, price_btc, _, _} <- Store.last_record(String.upcase(ticker) <> "_BTC") do
      {:ok, %{
        datetime: datetime,
        price_btc: price_btc,
        price_usd: price_usd,
        marketcap: marketcap,
        volume: volume
      }}
    else
      {:error, reason} ->
        {:error, "Cannot fetch price for ticker #{ticker}: #{reason}"}

      _ ->
        {:error, "Cannot fetch price for ticker #{ticker}"}
    end
  end

  defp hist_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceBtc: true,
         priceUsd: true
       }) do
    pair_btc = String.upcase(ticker) <> "_BTC"
    pair_usd = String.upcase(ticker) <> "_USD"

    result_btc = get_price_points(pair_btc, from, to, interval)
    result_usd = get_price_points(pair_usd, from, to, interval)

    # The data is always in _USD and _BTC measurements, but with a slightly different
    # timestamp. Zip combines corresponding results
    result =
      Enum.zip(result_btc, result_usd)
      |> Enum.map(fn {%{datetime: ltime} = btc_map, %{datetime: rtime, price_usd: price_usd}} ->
           IO.inspect(DateTime.to_unix(ltime) - DateTime.to_unix(rtime))
           Map.put(btc_map, :price_usd, price_usd)
         end)

    {:ok, result}
  end

  defp hist_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceBtc: true
       }) do
    pair = String.upcase(ticker) <> "_BTC"
    result = get_price_points(pair, from, to, interval)
    {:ok, result}
  end

  defp hist_price(%{ticker: ticker, from: from, to: to, interval: interval}, %{
         priceUsd: true
       }) do
    pair = String.upcase(ticker) <> "_USD"
    result = get_price_points(pair, from, to, interval)
    {:ok, result}
  end

  defp hist_price(args, fields) do
    Logger.warn("Unexpected arguments passed to hist_price")
  end

  defp requested_fields(context) do
    fields =
      context.definition.selections
      |> Enum.map(&(Map.get(&1, :name) |> String.to_atom()))
      |> Enum.into(%{}, fn field -> {field, true} end)
  end

  defp to_price_point([datetime, price, volume, marketcap]) do
    %{
      datetime: datetime,
      price_btc: price,
      price_usd: price,
      marketcap: marketcap,
      volume: volume
    }
  end

  defp get_price_points(pair, from, to, interval) do
    Sanbase.Prices.Store.fetch_prices_with_resolution(
      pair,
      from,
      to,
      interval
    )
    |> IO.inspect()
    |> Enum.map(&to_price_point/1)
  end
end