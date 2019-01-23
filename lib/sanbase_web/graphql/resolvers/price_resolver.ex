defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import Absinthe.Resolution.Helpers

  alias SanbaseWeb.Graphql.InfluxdbDataloader
  alias Sanbase.Model.Project
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.DateTimeUtils

  @total_market "TOTAL_MARKET"
  @total_market_measurement "TOTAL_MARKET_total-market"

  @doc """
    Returns a list of price points for the given ticker. Optimizes the number of queries
    to the DB by inspecting the requested fields.
  """
  @deprecated "Use history price by slug instead of ticker"
  def history_price(_root, %{ticker: @total_market} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(InfluxdbDataloader, {:price, @total_market_measurement}, args)
    |> on_load(&total_market_history_price_on_load(&1, args))
  end

  @doc """
    Returns a list of price points for the given ticker. Optimizes the number of queries
    to the DB by inspecting the requested fields.
  """
  def history_price(_root, %{slug: @total_market} = args, %{context: %{loader: loader}}) do
    loader
    |> Dataloader.load(InfluxdbDataloader, {:price, @total_market_measurement}, args)
    |> on_load(&total_market_history_price_on_load(&1, args))
  end

  @deprecated "Use history price by slug"
  def history_price(_root, %{ticker: ticker} = args, %{context: %{loader: loader}}) do
    with slug when not is_nil(slug) <- Project.slug_by_ticker(ticker) do
      ticker_cmc_id = ticker <> "_" <> slug

      loader
      |> Dataloader.load(InfluxdbDataloader, {:price, ticker_cmc_id}, args)
      |> on_load(&history_price_on_load(&1, ticker_cmc_id, args))
    else
      error ->
        {:error, "Cannot fetch history price for #{ticker}. Reason: #{inspect(error)}"}
    end
  end

  def history_price(_root, %{slug: slug} = args, %{context: %{loader: loader}}) do
    with ticker when not is_nil(ticker) <- Project.ticker_by_slug(slug) do
      ticker_cmc_id = ticker <> "_" <> slug

      loader
      |> Dataloader.load(InfluxdbDataloader, {:price, ticker_cmc_id}, args)
      |> on_load(&history_price_on_load(&1, ticker_cmc_id, args))
    else
      error ->
        {:error, "Cannot fetch history price for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  def ohlc(_root, %{slug: slug} = args, _context) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(slug),
         true <- DateTimeUtils.valid_interval_string?(args.interval),
         {:ok, prices} <-
           Sanbase.Prices.Store.fetch_ohlc(
             measurement,
             args.from,
             args.to,
             args.interval
           ) do
      result =
        prices
        |> Enum.map(fn [dt, open, high, low, close, _] ->
          %{
            datetime: dt,
            open_price_usd: open,
            high_price_usd: high,
            low_price_usd: low,
            close_price_usd: close
          }
        end)

      {:ok, result}
    else
      error ->
        {:error, "Cannot fetch ohlc for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  def multiple_projects_stats(_root, %{slugs: slugs} = args, _context) do
    with {:ok, measurement_slug_map} <- Measurement.names_from_slugs(slugs),
         {:ok, values} <-
           Sanbase.Prices.Store.fetch_volume_mcap_multiple_measurements(
             measurement_slug_map,
             args.from,
             args.to
           ) do
      {:ok,
       values
       |> Enum.map(fn
         {slug, volume, mcap, percent} ->
           %{slug: slug, volume: volume, marketcap: mcap, marketcap_percent: percent}
       end)}
    else
      _ ->
        {:error, "Can't fetch combined volume and marketcap for slugs"}
    end
  end

  # Private functions

  defp total_market_history_price_on_load(loader, args) do
    with {:ok, usd_prices} <-
           Dataloader.get(loader, InfluxdbDataloader, {:price, @total_market_measurement}, args) do
      result =
        usd_prices
        |> Enum.map(fn [dt, _, _, marketcap_usd, volume_usd] ->
          %{
            datetime: dt,
            marketcap: marketcap_usd,
            volume: volume_usd
          }
        end)

      {:ok, result}
    else
      _ ->
        {:error, "Can't fetch total marketcap prices"}
    end
  end

  defp history_price_on_load(loader, ticker_cmc_id, args) do
    with {:ok, prices} <-
           Dataloader.get(loader, InfluxdbDataloader, {:price, ticker_cmc_id}, args) do
      result =
        prices
        |> Enum.map(fn [dt, usd_price, btc_price, marketcap_usd, volume_usd] ->
          %{
            datetime: dt,
            price_btc: btc_price,
            price_usd: usd_price,
            marketcap: marketcap_usd,
            volume: volume_usd
          }
        end)

      {:ok, result}
    else
      _ ->
        {:error, "Can't fetch prices for #{ticker_cmc_id}"}
    end
  end
end
