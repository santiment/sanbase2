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
  alias Sanbase.Cryptocompare.Handler
  alias Sanbase.Cryptocompare.OpenInterest.HistoricalWorker

  @oban_conf_name :oban_scrapers
  # @unique_peroid 60 * 86_400
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
      Logger.info("[Cryptocompare Historical] Start exporting OpenInterest historical data.")
      resume()
    else
      Logger.info("[Cryptocompare Historical] OpenInterest historical scheduler is not enabled.")
    end

    {:ok, %{}}
  end

  def enabled?(), do: Config.module_get(__MODULE__, :enabled?) |> String.to_existing_atom()

  def schedule_previous_day_jobs(opts \\ []) do
    # This job needs to scrape only the previous day of data. It does not need to scrape
    # historical data. Because of this it does not schedule next jobs.
    # It fetches 1 value per minute, bu the limit is 2000 so we can fill some gaps, if they
    # exist.
    limit = Keyword.get(opts, :limit, HistoricalWorker.default_limit())
    schedule_next_job = Keyword.get(opts, :schedule_next_job, false)
    beginning_of_day = DateTime.utc_now() |> Timex.beginning_of_day() |> DateTime.to_unix()

    {:ok, markets_and_instruments} = Handler.get_markets_and_instruments()

    for {market, instruments} <- markets_and_instruments, instrument <- instruments do
      new_job(market, instrument, beginning_of_day, schedule_next_job, limit)
    end
    |> Enum.chunk_every(200)
    |> Enum.each(&Oban.insert_all(@oban_conf_name, &1))
  end

  def schedule_jobs(opts \\ []) do
    limit = Keyword.fetch!(opts, :limit)
    schedule_next_job = Keyword.get(opts, :schedule_next_job, false)

    # Scrape the last `limit` number of data points.
    to_datetime = DateTime.utc_now() |> DateTime.to_unix()

    {:ok, markets_and_instruments} = Handler.get_markets_and_instruments()

    for {market, instruments} <- markets_and_instruments, instrument <- instruments do
      new_job(market, instrument, to_datetime, schedule_next_job, limit)
    end
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
end
