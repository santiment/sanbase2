defmodule SanbaseWeb.Graphql.Resolvers.PriceResolver do
  require Logger

  import SanbaseWeb.Graphql.Helpers.Utils, only: [calibrate_interval: 6]

  alias Sanbase.Model.Project
  alias Sanbase.Influxdb.Measurement
  alias Sanbase.DateTimeUtils
  alias Sanbase.Prices.Store

  @total_market "TOTAL_MARKET"
  @total_market_measurement "TOTAL_MARKET_total-market"
  @total_erc20 "TOTAL_ERC20"

  @doc """
    Returns a list of price points for the given ticker. Optimizes the number of queries
    to the DB by inspecting the requested fields.
  """
  def history_price(
        _root,
        %{ticker: @total_market, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Store, @total_market_measurement, from, to, interval, 300),
         {:ok, result} <-
           Store.fetch_prices_with_resolution(@total_market_measurement, from, to, interval) do
      {:ok, result |> map_price_data()}
    end
  end

  @doc """
    Returns a list of price points for the given ticker. Optimizes the number of queries
    to the DB by inspecting the requested fields.
  """
  def history_price(
        _root,
        %{slug: @total_market, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Store, @total_market_measurement, from, to, interval, 300),
         {:ok, result} <-
           Store.fetch_prices_with_resolution(@total_market_measurement, from, to, interval) do
      {:ok, result |> map_price_data()}
    end
  end

  def history_price(
        _root,
        %{slug: @total_erc20, from: from, to: to, interval: interval},
        _resolution
      ) do
    with {:ok, from, to, interval} <-
           calibrate_interval(Store, @total_market_measurement, from, to, interval, 300),
         {:ok, result} <-
           Store.fetch_prices_with_resolution(@total_erc20, from, to, interval) do
      {:ok, result}
    end
  end

  def history_price(_root, %{ticker: ticker, from: from, to: to, interval: interval}, _resolution) do
    with {:get_slug, slug} when not is_nil(slug) <- {:get_slug, Project.slug_by_ticker(ticker)},
         ticker_cmc_id <- ticker <> "_" <> slug,
         {:ok, from, to, interval} <-
           calibrate_interval(Store, slug, from, to, interval, 300),
         {:ok, result} <- Store.fetch_prices_with_resolution(ticker_cmc_id, from, to, interval) do
      {:ok, result |> map_price_data()}
    else
      {:get_slug, nil} ->
        {:error,
         "The provided ticker '#{ticker}' is misspelled or there is no data for this ticker"}

      error ->
        {:error, "Cannot fetch history price for #{ticker}. Reason: #{inspect(error)}"}
    end
  end

  def history_price(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with {:get_ticker, ticker} when not is_nil(ticker) <-
           {:get_ticker, Project.ticker_by_slug(slug)},
         ticker_cmc_id <- ticker <> "_" <> slug,
         {:ok, from, to, interval} <-
           calibrate_interval(Store, slug, from, to, interval, 300),
         {:ok, result} <- Store.fetch_prices_with_resolution(ticker_cmc_id, from, to, interval) do
      {:ok, result |> map_price_data()}
    else
      {:get_ticker, nil} ->
        {:error, "The provided slug '#{slug}' is misspelled or there is no data for this slug"}

      error ->
        {:error, "Cannot fetch history price for #{slug}. Reason: #{inspect(error)}"}
    end
  end

  def ohlc(_root, %{slug: slug, from: from, to: to, interval: interval}, _resolution) do
    with measurement when not is_nil(measurement) <- Measurement.name_from_slug(slug),
         true <- DateTimeUtils.valid_interval_string?(interval),
         {:ok, prices} <-
           Sanbase.Prices.Store.fetch_ohlc(
             measurement,
             from,
             to,
             interval
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

  def multiple_projects_stats(_root, %{slugs: slugs, from: from, to: to}, _resolution) do
    with {:ok, measurement_slug_map} <- Measurement.names_from_slugs(slugs),
         {:ok, values} <-
           Sanbase.Prices.Store.fetch_volume_mcap_multiple_measurements(
             measurement_slug_map,
             from,
             to
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

  defp map_price_data(data) do
    data
    |> Enum.map(fn [dt, usd_price, btc_price, marketcap_usd, volume_usd] ->
      %{
        datetime: dt,
        price_btc: btc_price,
        price_usd: usd_price,
        marketcap: marketcap_usd,
        volume: volume_usd
      }
    end)
  end
end
