defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import Absinthe.Resolution.Helpers
  import Ecto.Query

  alias SanbaseWeb.Graphql.PriceStore

  @doc """
  Returns a list of price points for the given ticker. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  @deprecated "Use history price by slug instead of ticker"
  def history_price(_root, %{ticker: "TOTAL_MARKET"} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PriceStore, "TOTAL_MARKET_total-market", args)
    |> on_load(fn loader ->
      with {:ok, usd_prices} <-
             Dataloader.get(loader, PriceStore, "TOTAL_MARKET_total-market", args) do
        result =
          usd_prices
          |> Enum.map(fn [dt, _, _, marketcap_usd, volume_usd] ->
            %{
              datetime: dt,
              marketcap: nil_or_decimal(marketcap),
              volume: nil_or_decimal(volume)
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch total marketcap prices"}
      end
    end)
  end

  @doc """
  Returns a list of price points for the given ticker. Optimizes the number of queries
  to the DB by inspecting the requested fields.
  """
  def history_price(_root, %{slug: "TOTAL_MARKET"} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(PriceStore, "TOTAL_MARKET_total-market", args)
    |> on_load(fn loader ->
      with {:ok, usd_prices} <-
             Dataloader.get(loader, PriceStore, "TOTAL_MARKET_total-market", args) do
        result =
          usd_prices
          |> Enum.map(fn [dt, _, _, marketcap_usd, volume_usd] ->
            %{
              datetime: dt,
              marketcap: Decimal.new(marketcap_usd),
              volume: Decimal.new(volume_usd)
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch total marketcap prices"}
      end
    end)
  end

  @deprecated "Use history price by slug"
  def history_price(_root, %{ticker: ticker} = args, %{context: %{loader: loader}}) do
    slug = slug_by_ticker(ticker)
    ticker_cmc_id = ticker <> "_" <> slug

    loader
    |> Dataloader.load(PriceStore, ticker_cmc_id, args)
    |> on_load(fn loader ->
      with {:ok, prices} <- Dataloader.get(loader, PriceStore, ticker_cmc_id, args) do
        result =
          prices
          |> Enum.map(fn [dt, usd_price, btc_price, marketcap_usd, volume_usd] ->
            %{
              datetime: dt,
              price_btc: nil_or_decimal(btc_price),
              price_usd: nil_or_decimal(usd_price),
              marketcap: nil_or_decimal(marketcap),
              volume: nil_or_decimal(volume)
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch prices for #{ticker}"}
      end
    end)
  end

  def history_price(_root, %{slug: slug} = args, %{context: %{loader: loader}}) do
    ticker = ticker_by_slug(slug)
    ticker_cmc_id = ticker <> "_" <> slug

    loader
    |> Dataloader.load(PriceStore, ticker_cmc_id, args)
    |> on_load(fn loader ->
      with {:ok, prices} <- Dataloader.get(loader, PriceStore, ticker_cmc_id, args) do
        result =
          prices
          # |> IO.inspect(label: "HISTORY PRICES FOR #{slug}")
          |> Enum.map(fn [dt, usd_price, btc_price, marketcap_usd, volume_usd] ->
            %{
              datetime: dt,
              price_btc: Decimal.new(btc_price),
              price_usd: Decimal.new(usd_price),
              marketcap: Decimal.new(marketcap_usd),
              volume: Decimal.new(volume_usd)
            }
          end)

        {:ok, result}
      else
        _ ->
          {:error, "Can't fetch prices for #{ticker}"}
      end
    end)
  end

  # Private functions

  defp nil_or_decimal(nil), do: nil

  defp nil_or_decimal(num) when is_number(num) do
    Decimal.new(num)
  end

  defp ticker_by_slug(slug) do
    from(
      p in Sanbase.Model.Project,
      where: p.coinmarketcap_id == ^slug and not is_nil(p.ticker),
      select: p.ticker
    )
    |> Sanbase.Repo.one()
  end

  @deprecated "This should no longer be used after price by ticker is removed"
  defp slug_by_ticker(ticker) do
    from(
      p in Sanbase.Model.Project,
      where: p.ticker == ^ticker and not is_nil(p.coinmarketcap_id),
      select: p.coinmarketcap_id
    )
    |> Sanbase.Repo.one()
  end
end
