defmodule Sanbase.Kaiko do
  alias Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress, as: Progress

  require Logger
  require Sanbase.Utils.Config, as: Config

  @prices_exporter :prices_exporter
  @source "kaiko"
  @url "https://eu.market-api.kaiko.io"
  @recv_timeout 30_000
  @interval "1s"
  @rounds_per_minute 12

  # Scraping is started every round minute. We want to scrape every 5 seconds.
  # Because of this, every minute scrape consists of many scrapres.
  def run(opts \\ []) do
    rounds = Keyword.get(opts, :rounds_per_minute, @rounds_per_minute)
    sleep_seconds = div(60, rounds)

    for i <- 1..rounds do
      do_run()
      # The last time there's no need for sleeping after the scraping
      if i != rounds, do: Process.sleep(sleep_seconds * 1000)
    end
  end

  defp do_run() do
    Logger.info("Scraping Kaiko prices for #{length(pairs())} pairs")

    now = Timex.now()
    naive_now = DateTime.to_naive(now) |> NaiveDateTime.truncate(:second)
    last_dt_map = Progress.last_scraped_all_source("kaiko")

    data =
      Sanbase.Parallel.map(
        pairs(),
        fn {base_asset, slug} ->
          # Build the timerange params. All `end_time` params are matching
          usd_timerange = get_timerange_params(base_asset, "usd", now, last_dt_map)
          btc_timerange = get_timerange_params(base_asset, "btc", now, last_dt_map)

          # Fetch the USD and BTC prices and combine them based on
          # the datetime. The datetime is rounded to `@interval_sec` buckets
          # so this combination can be done in more cases
          usd_prices = current_prices(base_asset, "usd", usd_timerange)
          btc_prices = current_prices(base_asset, "btc", btc_timerange)
          prices = combine_prices(usd_prices, btc_prices)

          :ok = export_to_kafka(prices, slug)

          [
            get_last_datetime(usd_prices, base_asset, "usd"),
            get_last_datetime(btc_prices, base_asset, "btc")
          ]
        end,
        max_concurrency: 50,
        map_type: :flat_map
      )
      |> Enum.reject(&is_nil/1)
      |> Enum.map(fn {identifier, dt} ->
        %{
          identifier: identifier,
          datetime: DateTime.to_naive(dt) |> NaiveDateTime.truncate(:second),
          source: @source,
          updated_at: naive_now,
          inserted_at: naive_now
        }
      end)

    Sanbase.Repo.insert_all(Progress, data,
      on_conflict: :replace_all,
      conflict_target: [:identifier, :source]
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
            |> DateTime.truncate(:second)
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

  defp last_datetime_scraped(slug, last_dt_map) do
    case Map.get(last_dt_map, slug) do
      nil -> Timex.shift(Timex.now(), minutes: -1)
      %NaiveDateTime{} = ndt -> DateTime.from_naive!(ndt, "Etc/UTC")
    end
  end

  def get_last_datetime(prices, base_asset, quote_asset) do
    identifier = identifier(base_asset, quote_asset)

    prices
    |> Enum.filter(& &1.price)
    |> Enum.max_by(fn elem -> elem.datetime end, DateTime, fn -> nil end)
    |> case do
      %{datetime: %DateTime{} = dt} ->
        {identifier, dt}

      _ ->
        nil
    end
  end

  defp get_timerange_params(base_asset, quote_asset, end_time, last_dt_map) do
    identifier = identifier(base_asset, quote_asset)

    %{
      start_time: last_datetime_scraped(identifier, last_dt_map),
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
