defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.PriceStore
  alias SanbaseWeb.Graphql.Helpers.Utils

  @doc """
  Returns a list of price points for the given ticker or slug. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  def history_price(root, %{slug: slug} = args, resolution) do
    # Temporary solution while all frontend queries migrate to using slug. After that
    # only the slug query will remain
    if ticker = Utils.ticker_by_slug(slug) do
      args = args |> Map.delete(:slug) |> Map.put(:ticker, ticker)
      history_price(root, args, resolution)
    else
      {:ok, []}
    end
  end

  def history_price(_root, %{ticker: "TOTAL_MARKET"} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PriceStore, "TOTAL_MARKET_USD", args)
    |> on_load(fn loader ->
      with {:ok, usd_prices} <- Dataloader.get(loader, PriceStore, "TOTAL_MARKET_USD", args) do
        result =
          usd_prices
          |> Enum.map(fn [dt, _, volume, marketcap] ->
            %{
              datetime: dt,
              marketcap: marketcap,
              volume: volume
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch total marketcap prices"}
      end
    end)
  end

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
              price_btc: btc_price,
              price_usd: usd_price,
              marketcap: marketcap,
              volume: volume
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
