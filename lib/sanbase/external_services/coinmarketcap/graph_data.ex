defmodule Sanbase.ExternalServices.Coinmarketcap.GraphData do
  defstruct [:market_cap_by_available_supply, :price_usd, :volume_usd]

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://graphs.coinmarketcap.com"
  plug Tesla.Middleware.Compression
  plug Tesla.Middleware.Logger

  alias Sanbase.ExternalServices.Coinmarketcap.GraphData
  alias Sanbase.ExternalServices.Coinmarketcap.RateLimiter
  alias Sanbase.Prices.Point

  @seconds_in_day 24 * 60 * 60 # Number of seconds in a day

  def fetch_all_time_prices(token) do
    graph_data_all_time_url(token)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        parse_json(body)
    end
  end

  def fetch_prices(token, from_datetime, to_datetime) do
    daily_ranges(from_datetime, to_datetime)
    |> Stream.flat_map(&extract_prices_for_interval_with_rate_limit(token, &1, &1 + @seconds_in_day))
  end

  def parse_json(json) do
    json
    |> Poison.decode!(as: %GraphData{})
    |> convert_to_price_points
  end

  defp convert_to_price_points(%GraphData{
    market_cap_by_available_supply: market_cap_by_available_supply,
    price_usd: price_usd,
    volume_usd: volume_usd
  }) do
    List.zip([market_cap_by_available_supply, price_usd, volume_usd])
    |> Stream.map(fn {[dt, marketcap], [dt, price], [dt, volume]} ->
      %Point{marketcap: marketcap, price: price, volume: volume, datetime: DateTime.from_unix!(dt, :millisecond)}
    end)
  end

  defp extract_prices_for_interval_with_rate_limit(token, start_interval, end_interval) do
    RateLimiter.wait()
    extract_prices_for_interval(token, start_interval, end_interval)
  end

  defp extract_prices_for_interval(token, start_interval, end_interval) do
    graph_data_interval_url(token, start_interval * 1000, end_interval * 1000)
    |> get()
    |> case do
      %{status: 200, body: body} ->
        parse_json(body)
    end
  end

  defp daily_ranges(from_datetime, to_datetime) when not is_number(from_datetime) and not is_number(to_datetime) do
    daily_ranges(DateTime.to_unix(from_datetime), DateTime.to_unix(to_datetime))
  end

  defp daily_ranges(from_datetime, to_datetime) do
    Stream.unfold(
      from_datetime,
      fn start_interval ->
        cond do
          start_interval <= to_datetime ->
            {start_interval, start_interval + @seconds_in_day}
          true -> nil
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
