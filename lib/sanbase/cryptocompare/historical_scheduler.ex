defmodule Sanbase.Cryptocompare.HistoricalScheduler do
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

  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2]

  alias Sanbase.Cryptocompare.HistoricalWorker

  require Logger
  require Sanbase.Utils.Config, as: Config

  @oban_conf_name :oban_scrapers
  @unique_peroid 60 * 86_400
  @oban_queue :cryptocompare_historical_jobs_queue

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
      Logger.info("[Cryptocompare Historical] Start exporting OHLCV historical data.")
      resume()
    end

    {:ok, %{}}
  end

  def enabled?(), do: Config.get(:enabled?) |> String.to_existing_atom()

  def add_jobs(base_asset, quote_asset, from, to) do
    start_time = DateTime.utc_now()
    recorded_dates = get_pair_dates(base_asset, quote_asset, from, to) |> MapSet.new()
    dates = generate_dates_inclusive(from, to)
    dates_to_insert = Enum.reject(dates, &(&1 in recorded_dates))

    result = do_add_jobs_no_uniqueness_check(base_asset, quote_asset, dates_to_insert)

    result_map = %{
      jobs_count_total: length(dates),
      jobs_already_present_count: MapSet.size(recorded_dates),
      jobs_inserted: length(result),
      time_elapsed: DateTime.diff(DateTime.utc_now(), start_time, :second)
    }

    Logger.info("""
    [Cryptocompare Historical] Scheduled #{result_map.jobs_inserted} new jobs \
    for the #{base_asset}/#{quote_asset} pair. Took: #{result_map.time_elapsed}s.
    """)

    {:ok, result_map}
  end

  def get_pair_dates(base_asset, quote_asset, from, to) do
    query = """
    SELECT args->>'date', inserted_at FROM oban_jobs
    WHERE args->>'base_asset' = $1 AND args->>'quote_asset' = $2 AND queue = $3

    UNION ALL

    SELECT args->>'date', inserted_at FROM finished_oban_jobs
    WHERE args->>'base_asset' = $1 AND args->>'quote_asset' = $2 AND queue = $3
    """

    {:ok, %{rows: rows}} =
      Ecto.Adapters.SQL.query(Sanbase.Repo, query, [
        base_asset,
        quote_asset,
        to_string(@oban_queue)
      ])

    now = NaiveDateTime.utc_now()

    rows
    |> Enum.filter(fn [_, inserted_at] ->
      NaiveDateTime.diff(now, inserted_at, :second) <= @unique_peroid
    end)
    |> Enum.map(fn [date, _] -> Date.from_iso8601!(date) end)
    |> Enum.filter(fn date -> Timex.between?(date, from, to, inclusive: true) end)
  end

  defp do_add_jobs_no_uniqueness_check(base_asset, quote_asset, dates) do
    data =
      dates
      |> Enum.map(fn date ->
        HistoricalWorker.new(%{
          base_asset: base_asset,
          quote_asset: quote_asset,
          date: date
        })
      end)

    Oban.insert_all(@oban_conf_name, data)
  end
end
