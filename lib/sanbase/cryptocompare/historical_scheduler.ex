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

  @oban_queue :cryptocompare_historical_jobs_queue

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def resume(), do: Oban.resume_queue(queue: @oban_queue)
  def pause(), do: Oban.pause_queue(queue: @oban_queue)

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
    # The jobs are added via Ecto.Multi instead of using Oban.insert_all as
    # the latter is not able to handle the uniqueness check and it's ignored.
    result =
      Ecto.Multi.new()
      |> add_jobs_to_multi(base_asset, quote_asset, from, to)
      |> Sanbase.Repo.transaction()

    case result do
      {:ok, map} ->
        total_jobs_count = map_size(map)
        unique_jobs_count = Enum.count(map, fn {_k, job} -> job.conflict? == false end)

        {:ok,
         inserted_unique_jobs_count: unique_jobs_count,
         ignored_non_unique_jobs_count: total_jobs_count - unique_jobs_count}

      error ->
        error
    end
  end

  defp add_jobs_to_multi(multi, base_asset, quote_asset, from, to) do
    generate_dates_inclusive(from, to)
    |> Enum.reduce(multi, fn date, multi ->
      key = {base_asset, quote_asset, date}
      job = HistoricalWorker.new(%{base_asset: base_asset, quote_asset: quote_asset, date: date})

      multi |> Oban.insert(key, job)
    end)
  end
end
