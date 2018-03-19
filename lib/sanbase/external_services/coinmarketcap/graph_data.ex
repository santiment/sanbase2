defmodule Sanbase.ExternalServices.Coinmarketcap.GraphData do
  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd, :price_btc]

  require Logger

  use Tesla

  alias Sanbase.ExternalServices.RateLimiting
  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.PricePoint
  alias Sanbase.ExternalServices.ErrorCatcher

  plug(RateLimiting.Middleware, name: :graph_coinmarketcap_rate_limiter)
  plug(ErrorCatcher.Middleware)
  plug(Tesla.Middleware.BaseUrl, "https://graphs2.coinmarketcap.com")
  plug(Tesla.Middleware.Compression)
  plug(Tesla.Middleware.Logger)

  # Number of seconds in a day
  @seconds_in_day 24 * 60 * 60

  def fetch_first_price_datetime(coinmarketcap_id) do
    fetch_all_time_prices(coinmarketcap_id)
    |> Enum.take(1)
    |> hd
    |> Map.get(:datetime)
  end

  def fetch_prices(coinmarketcap_id, from_datetime, to_datetime) do
    day_ranges(from_datetime, to_datetime)
    |> Stream.flat_map(&extract_prices_for_interval(coinmarketcap_id, &1))
  end

  # Helper functions

  defp json_to_price_points(json) do
    json
    |> Poison.decode!(as: %GraphData{})
    |> convert_to_price_points()
  end

  defp fetch_all_time_prices(coinmarketcap_id) do
    graph_data_all_time_url(coinmarketcap_id)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()
    end
  end

  defp convert_to_price_points(%GraphData{
         market_cap_by_available_supply: market_cap_by_available_supply,
         price_usd: price_usd,
         volume_usd: volume_usd,
         price_btc: price_btc
       }) do
    List.zip([market_cap_by_available_supply, price_usd, volume_usd, price_btc])
    |> Stream.map(fn {[dt, marketcap], [dt, price_usd], [dt, volume_usd], [dt, price_btc]} ->
      %PricePoint{
        marketcap: marketcap,
        price_usd: price_usd,
        volume_usd: volume_usd,
        price_btc: price_btc,
        datetime: DateTime.from_unix!(dt, :millisecond)
      }
    end)
  end

  defp extract_prices_for_interval(coinmarketcap_id, {start_interval, end_interval}) do
    graph_data_interval_url(coinmarketcap_id, start_interval * 1000, end_interval * 1000)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        body |> json_to_price_points()

      _ ->
        Logger.error("Failed to fetch graph data for interval")
        []
    end
  end

  defp day_ranges(from_datetime, to_datetime)
       when not is_number(from_datetime) and not is_number(to_datetime) do
    day_ranges(DateTime.to_unix(from_datetime), DateTime.to_unix(to_datetime))
  end

  defp day_ranges(from_datetime, to_datetime) do
    Stream.unfold(from_datetime, fn start_interval ->
      if start_interval <= to_datetime do
        {
          {start_interval, start_interval + @seconds_in_day},
          start_interval + @seconds_in_day
        }
      else
        nil
      end
    end)
  end

  defp graph_data_all_time_url(ticker) do
    "/currencies/#{ticker}/"
  end

  defp graph_data_interval_url(ticker, from_timestamp, to_timestamp) do
    "/currencies/#{ticker}/#{from_timestamp}/#{to_timestamp}/"
  end
end
