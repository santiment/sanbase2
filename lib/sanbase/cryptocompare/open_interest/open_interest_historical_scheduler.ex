defmodule Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler do
  @moduledoc ~s"""
  Scrape the prices from Cryptocompare websocket API
  https://min-api.cryptocompare.com/documentation/websockets

  Use the cryptocompare API to fetch prices aggregated across many exchanges
  in near-realtime. For every base/quote asset pairs fetch:
    - price
    - volume 24h (sliding window) - in number of tokens and in the quote asset currency
    - top tier exchanges volume 24h (sliding window) - in number of tokens and
      in the quote asset currency
  """

  use GenServer

  require Logger
  alias Sanbase.Utils.Config

  @oban_conf_name :oban_scrapers
  @unique_peroid 60 * 86_400
  @oban_queue :cryptocompare_open_interest_historical_jobs_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def queue(), do: @oban_queue
  def resume(), do: Oban.resume_queue(@oban_conf_name, queue: @oban_queue)
  def pause(), do: Oban.pause_queue(@oban_conf_name, queue: @oban_queue)
  def conf_name(), do: @oban_conf_name

  def init(_opts) do
    # In order to be able to stop the historical scraper via env variables
    # the queue is defined as paused and should be resumed from code.
    if enabled?() do
      Logger.info("[Cryptocompare Historical] Start exporting Open Interest historical data.")
      resume()
    else
      Logger.info("[Cryptocompare Historical] Open Interest historical scheduler is not enabled.")
    end

    {:ok, %{}}
  end

  def enabled?(), do: Config.module_get(__MODULE__, :enabled?) |> String.to_existing_atom()

  def schedule_previous_day_jobs(opts \\ []) do
    limit = Keyword.get(opts, :limit, 30)
    schedule_next_job = Keyword.get(opts, :schedule_next_job, false)
    beginning_of_day = DateTime.utc_now() |> Timex.beginning_of_day() |> DateTime.to_unix()

    get_markets_and_instruments()
    |> Enum.flat_map(fn {market, instruments} ->
      for instrument <- instruments do
        new_job(market, instrument, beginning_of_day, schedule_next_job, limit)
      end
    end)
    |> Enum.chunk_every(200)
    |> Enum.each(&Oban.insert_all(@oban_conf_name, &1))
  end

  def add_job(market, instrument, timestamp, schedule_next_job, limit) do
    job = new_job(market, instrument, timestamp, schedule_next_job, limit)
    Oban.insert(@oban_conf_name, job)
  end

  defp new_job(market, instrument, timestamp, schedule_next_job, limit) do
    Sanbase.Cryptocompare.OpenInterest.HistoricalWorker.new(%{
      market: market,
      instrument: instrument,
      timestamp: timestamp,
      schedule_next_job: schedule_next_job,
      limit: limit
    })
  end

  defp get_markets_and_instruments() do
    url = "https://data-api.cryptocompare.com/futures/v1/markets/instruments"
    headers = [{"authorization", "Apikey #{api_key()}"}]

    case HTTPoison.get(url, headers, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        market_mapped_instruments_map = parse_markets_instruments_response(body)

        {:ok, market_mapped_instruments_map}

      {:ok, %HTTPoison.Response{status_code: status_code, body: body}} ->
        Logger.error("""
        [Cryptocompare Historical] Failed to get markets. Status code: #{status_code}. \
        Body: #{body}
        """)

        {:error, "Failed to get markets"}

      {:error, error} ->
        Logger.error("""
        [Cryptocompare Historical] Failed to get markets. Error: #{inspect(error)}
        """)

        {:error, "Failed to get markets"}
    end
  end

  defp parse_markets_instruments_response(json_body) do
    # Filter the list so only 3 markets and BTC/ETH instruments are left
    json_body
    |> Jason.decode!()
    |> Map.get("Data")
    |> Enum.filter(fn {k, _} -> k in ["binance", "bybit", "deribit"] end)
    |> Enum.map(fn {market, data} ->
      mapped_instruments =
        data["instruments"]
        |> Enum.filter(fn {k, v} ->
          String.contains?(k, ["BTC", "ETH"]) and v["HAS_OPEN_INTEREST_UPDATES"]
        end)
        |> Enum.map(fn {k, _} -> k end)

      {market, mapped_instruments}
    end)
    |> Map.new()
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
end
