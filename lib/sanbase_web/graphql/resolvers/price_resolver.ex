defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.PriceStore

  @doc """
  Returns a list of price points for the given ticker. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  def history_price(_root, %{ticker: ticker} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PriceStore, String.upcase(ticker) <> "_USD", args)
    |> Dataloader.load(PriceStore, String.upcase(ticker) <> "_BTC", args)
    |> on_load(fn loader ->
      with {:ok, usd_prices} <-
             Dataloader.get(loader, PriceStore, String.upcase(ticker) <> "_USD", args),
           {:ok, btc_prices} <-
             Dataloader.get(loader, PriceStore, String.upcase(ticker) <> "_BTC", args) do
        # Zip the price in USD and BTC so they are shown as a single price point
        result =
          Enum.zip(btc_prices, usd_prices)
          |> Enum.map(fn {[dt, btc_price, volume, marketcap], [_, usd_price, _, _]} ->
            %{
              datetime: dt,
              price_btc: Decimal.new(btc_price),
              price_usd: Decimal.new(usd_price),
              marketcap: Decimal.new(marketcap),
              volume: Decimal.new(volume)
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch prices for #{ticker}"}
      end
    end)
  end
end
