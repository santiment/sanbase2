defmodule Sanbase.Kaiko do
  alias Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress, as: Progress

  import Sanbase.DateTimeUtils, only: [round_datetime: 2]
  require Logger
  require Sanbase.Utils.Config, as: Config

  @prices_exporter :prices_exporter
  @source "kaiko"
  @url "https://eu.market-api.kaiko.io"
  @recv_timeout 30_000
  @interval "10s"
  @interval_sec 10

  def run(opts \\ []) do
    # cronjobs cannot use sub-minute intervals.
    # The cronjob runs every 30 seconds by starting it twice, the second time
    # with a sleep: 30_000 argument, so it sleeps for 30 seconds before running
    if milliseconds = Keyword.get(opts, :sleep), do: Process.sleep(milliseconds)

    Logger.info("Scraping Kaiko prices for #{length(pairs())} pairs")

    now = Timex.now()

    Sanbase.Parallel.map(
      pairs(),
      fn {base_asset, slug} ->
        # Build the timerange params. All `end_time` params are matching
        usd_timerange = get_timerange_params(base_asset, "usd", now)
        btc_timerange = get_timerange_params(base_asset, "btc", now)

        # Fetch the USD and BTC prices and combine them based on
        # the datetime. The datetime is rounded to `@interval_sec` buckets
        # so this combination can be done in more cases
        usd_prices = current_prices(base_asset, "usd", usd_timerange)
        btc_prices = current_prices(base_asset, "btc", btc_timerange)
        prices = combine_prices(usd_prices, btc_prices)

        :ok = export_to_kafka(prices, slug)

        :ok = store_last_datetime(usd_prices, base_asset, "usd")
        :ok = store_last_datetime(btc_prices, base_asset, "btc")
      end
    )
  end

  def current_prices(base_asset, quote_asset, timerange) do
    url = latest_prices_url(base_asset, quote_asset, timerange)

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- get(url),
         {:ok, %{"data" => data}} <- Jason.decode(body) do
      # Round the datetimes, so the combining of USD and BTC prices can be done.
      # It is expected that the timestamps come in already rounded but this is
      # done just to make sure
      data
      |> Enum.map(fn elem ->
        %{
          price: elem["price"] |> Sanbase.Math.to_float(),
          datetime:
            elem["timestamp"]
            |> DateTime.from_unix!(:millisecond)
            |> round_datetime(@interval_sec)
        }
      end)
    else
      _ ->
        []
    end
    |> Enum.filter(& &1.price)
  end

  # execute authenticated request

  defp identifier(base_asset, quote_asset), do: base_asset <> "/" <> quote_asset

  defp get(url) do
    headers = [{"X-Api-Key", Config.get(:apikey)}]
    options = [recv_timeout: @recv_timeout]
    HTTPoison.get(url, headers, options)
  end

  defp latest_prices_url(base_asset, quote_asset, timerange) do
    opts = %{
      start_time: Map.get(timerange, :start_time) |> DateTime.to_iso8601(),
      end_time: Map.get(timerange, :end_time) |> DateTime.to_iso8601(),
      interval: Map.get(timerange, :interval)
    }

    @url <>
      "/v2/data/trades.v1/spot_exchange_rate/#{base_asset}/#{quote_asset}?" <>
      URI.encode_query(opts)
  end

  defp last_datetime_scraped(slug) do
    case Progress.last_scraped(slug, @source) do
      nil -> Timex.shift(Timex.now(), minutes: -10)
      %DateTime{} = dt -> dt
    end
  end

  def store_last_datetime(prices, base_asset, quote_asset) do
    identifier = identifier(base_asset, quote_asset)

    prices
    |> Enum.filter(& &1.price)
    |> Enum.max_by(fn elem -> elem.datetime end, DateTime, fn -> nil end)
    |> case do
      %{datetime: %DateTime{} = dt} ->
        {:ok, _} = Progress.store_progress(identifier, @source, dt)
        :ok

      _ ->
        :ok
    end
  end

  defp get_timerange_params(base_asset, quote_asset, end_time) do
    %{
      start_time: identifier(base_asset, quote_asset) |> last_datetime_scraped(),
      end_time: end_time,
      interval: @interval
    }
  end

  def combine_prices(usd_prices, btc_prices) do
    usd_map = Map.new(usd_prices, &{&1.datetime, %{price_usd: &1.price}})
    btc_map = Map.new(btc_prices, &{&1.datetime, %{price_btc: &1.price}})

    Map.merge(usd_map, btc_map, fn _datetime, map_usd, map_btc ->
      Map.merge(map_usd, map_btc)
    end)
    |> Enum.map(fn {datetime, map} ->
      # map contains price_usd, price_btc or both in case there are both prices
      # for the same datetime and the Map.merge/3 function was triggered.
      # The call to Map.merge/2 here overrides the prices that are present
      # in the map parameter
      %{
        price_usd: nil,
        price_btc: nil,
        marketcap_usd: nil,
        volume_usd: nil
      }
      |> Map.merge(map)
      |> Map.put(:datetime, datetime)
    end)
    |> Enum.reject(fn elem -> is_nil(elem.price_usd) and is_nil(elem.price_btc) end)
    |> Enum.sort_by(& &1.datetime, {:asc, DateTime})
  end

  defp export_to_kafka(prices, slug) do
    Enum.map(
      prices,
      fn %{price_usd: price_usd, price_btc: price_btc, datetime: datetime} ->
        key = @source <> "_" <> slug <> "_" <> DateTime.to_iso8601(datetime)

        value =
          %{
            timestamp: DateTime.to_unix(datetime),
            source: @source,
            slug: slug,
            price_usd: price_usd,
            price_btc: price_btc,
            marketcap_usd: nil,
            volume_usd: nil
          }
          |> Jason.encode!()

        {key, value}
      end
    )
    |> Sanbase.KafkaExporter.persist_sync(@prices_exporter)
  end

  defp pairs() do
    Sanbase.Model.Project.SourceSlugMapping.get_source_slug_mappings(@source)
  end
end
