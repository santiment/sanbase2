defmodule Sanbase.Kaiko do
  alias Sanbase.ExternalServices.Coinmarketcap.PriceScrapingProgress, as: Progress

  require Logger
  require Sanbase.Utils.Config, as: Config

  @prices_exporter :prices_exporter
  @source "kaiko"
  @url "https://eu.market-api.kaiko.io"
  @recv_timeout 30_000

  def run(opts \\ []) do
    # cronjobs cannot use sub-minute intervals.
    # The cronjob runs every 30 seconds by starting it twice, the second time
    # with a sleep: 30_000 argument, so it sleeps for 30 seconds before running
    if milliseconds = Keyword.get(opts, :sleep), do: Process.sleep(milliseconds)

    Logger.info("Scraping Kaiko prices for #{length(pairs())} pairs")

    Sanbase.Parallel.map(
      pairs(),
      fn {base_asset, quote_asset, slug} ->
        identifier = base_asset <> "/" <> quote_asset

        timerange = %{
          start_time: last_datetime_scraped(identifier),
          end_time: Timex.now(),
          interval: "10s"
        }

        prices =
          current_prices(base_asset, quote_asset, timerange)
          |> Enum.filter(& &1.price)

        last_datapoint =
          prices
          |> Enum.max_by(fn elem -> elem.datetime end, DateTime, fn -> nil end)

        :ok = export_to_kafka(slug, quote_asset, prices)

        case last_datapoint do
          %{datetime: %DateTime{} = dt} ->
            {:ok, _} = Progress.store_progress(identifier, @source, dt)
            :ok

          _ ->
            :ok
        end
      end
    )
  end

  def current_prices(base_asset, quote_asset, timerange) do
    url = latest_prices_url(base_asset, quote_asset, timerange)

    with {:ok, %HTTPoison.Response{status_code: 200, body: body}} <- get(url),
         {:ok, %{"data" => data}} <- Jason.decode(body) do
      data
      |> Enum.map(fn elem ->
        %{
          price: elem["price"] |> Sanbase.Math.to_float(),
          datetime: elem["timestamp"] |> DateTime.from_unix!(:millisecond)
        }
      end)
    else
      _ ->
        []
    end
  end

  # execute authenticated request

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

  defp export_to_kafka(slug, quote_asset, prices) when quote_asset in ["btc", "usd"] do
    Enum.map(
      prices,
      fn %{price: price, datetime: datetime} ->
        key = @source <> "_" <> slug <> "_" <> DateTime.to_iso8601(datetime)

        value =
          %{
            timestamp: DateTime.to_unix(datetime),
            source: @source,
            slug: slug,
            price_usd: (quote_asset == "usd" && price) || nil,
            price_btc: (quote_asset == "btc" && price) || nil,
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
    |> Enum.flat_map(fn {kaiko_code, santiment_slug} ->
      [{kaiko_code, "usd", santiment_slug}, {kaiko_code, "btc", santiment_slug}]
    end)
  end
end
