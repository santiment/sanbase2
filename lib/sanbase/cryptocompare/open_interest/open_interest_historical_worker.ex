defmodule Sanbase.Cryptocompare.OpenInterest.HistoricalWorker do
  @moduledoc ~s"""
  An Oban Worker that processes the jobs in the cryptocompare_historical_jobs_queue
  queue.

  An Oban Worker has one main function `perform/1` which receives as argument
  one record from the oban jobs table. If it returns :ok or {:ok, _}, then the
  job is considered successful and is completed. In order to have retries in case
  of Kafka downtime, the export to Kafka is done via persist_sync/2. This guarantees
  that if get_data/3 and export_data/1 return :ok, then the data is in Kafka.

  If perform/1 returns :error or {:error, _} then the task is scheduled for retry.
  An exponential backoff algorithm is used in order to decide when to retry. The
  default 20 attempts and the default algorithm used first retry after some seconds
  and the last attempt is done after about 3 weeks.
  """
  @queue :cryptocompare_open_interest_historical_jobs_queue
  use Oban.Worker,
    queue: @queue,
    unique: [period: 60 * 86_400]

  alias Sanbase.Utils.Config
  alias Sanbase.Cryptocompare.OHLCOpenInterestPoint
  alias Sanbase.Cryptocompare.HTTPHeaderUtils
  alias Sanbase.Cryptocompare.ExporterProgress

  require Logger

  @url "https://data-api.cryptocompare.com/futures/v1/historical/open-interest/hours"
  @limit 2000
  @oban_conf_name :oban_scrapers
  @topic :open_interest_ohlc_topic

  def queue(), do: @queue
  def conf_name(), do: @oban_conf_name

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"market" => market, "instrument" => instrument, "timestamp" => timestamp} = args

    limit = Map.get(args, "limit", @limit)

    case get_data(market, instrument, limit, timestamp) do
      {:ok, data} ->
        :ok = export_data(data)

        if data != [] do
          {min, max} = Enum.min_max_by(data, & &1.timestamp)
          :ok = maybe_schedule_next_job(min.timestamp, args)

          {:ok, _} =
            ExporterProgress.create_or_update(
              "#{market}_#{instrument}",
              to_string(@queue),
              min.timestamp,
              max.timestamp
            )
        end

        :ok

      {:error, :first_timestamp_reached} ->
        # This is the earliest record; do not return error and do not schedule another jobs
        :ok

      {:error, error} ->
        {:error, error}
    end
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(5)

  # Private functions

  @spec get_data(String.t(), String.t(), non_neg_integer(), non_neg_integer()) ::
          {:error, HTTPoison.Error.t()} | {:ok, any}
  def get_data(market, instrument, limit, timestamp) do
    query_params = [
      market: market,
      instrument: instrument,
      to_ts: timestamp,
      limit: limit
    ]

    headers = [{"authorization", "Apikey #{api_key()}"}]

    url = @url <> "?" <> URI.encode_query(query_params)

    case HTTPoison.get(url, headers, recv_timeout: 15_000) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body} = resp} ->
        case HTTPHeaderUtils.rate_limited?(resp) do
          false ->
            timestamps =
              ExporterProgress.get_timestamps(
                "#{market}_#{instrument}",
                to_string(@queue)
              )

            process_json_response(body, timestamps)

          {:error_limited, %{value: rate_limited_seconds}} ->
            handle_rate_limit(rate_limited_seconds)
        end

      {:ok, %HTTPoison.Response{status_code: 404}} ->
        # The error is No HOUR entries available on or before <timestamp>
        {:error, :first_timestamp_reached}

      {:error, error} ->
        {:error, error}
    end
  end

  defp handle_rate_limit(rate_limited_seconds) do
    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.pause()

    data =
      %{"type" => "resume"}
      |> Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker.new(
        schedule_in: rate_limited_seconds
      )

    Oban.insert(@oban_conf_name, data)

    {:error, :rate_limit}
  end

  defp process_json_response(json, timestamps) do
    data =
      json
      |> Jason.decode!()
      |> get_in(["Data"])
      |> Enum.map(fn map ->
        %{
          timestamp: map["TIMESTAMP"],
          market: map["MARKET"],
          instrument: map["INSTRUMENT"],
          mapped_instrument: map["MAPPED_INSTRUMENT"],
          index_underlying: map["INDEX_UNDERLYING"],
          quote_currency: map["QUOTE_CURRENCY"],
          settlement_currency: map["SETTLEMENT_CURRENCY"],
          contract_currency: map["CONTRACT_CURRENCY"],
          open_settlement: map["OPEN_SETTLEMENT"],
          open_mark_price: map["OPEN_MARK_PRICE"],
          open_quote: map["OPEN_QUOTE"],
          high_settlement: map["HIGH_SETTLEMENT"],
          high_mark_price: map["HIGH_MARK_PRICE"],
          high_quote: map["HIGH_QUOTE"],
          close_settlement: map["CLOSE_SETTLEMENT"],
          close_mark_price: map["CLOSE_MARK_PRICE"],
          close_quote: map["CLOSE_QUOTE"],
          low_settlement: map["LOW_SETTLEMENT"],
          low_mark_price: map["LOW_MARK_PRICE"],
          low_quote: map["LOW_QUOTE"]
        }
      end)
      |> then(fn list ->
        # Filter out all the data points for which we already have data.
        # This works with the assumption that the data is exported in a
        # specific way. The API accepts a timestamp and a limit and returns
        # `limit` number of data points before `timestamp`. When this is done
        # a new job is scheduled with the timestamp of the earliest data point,
        # thus going back in history.
        case timestamps do
          nil -> list
          {min, max} -> list |> Enum.reject(&(&1.timestamp in min..max))
        end
      end)

    # Create a new job with `first_timetamp`
    {:ok, data}
  end

  defp maybe_schedule_next_job(
         min_timestamp,
         %{"schedule_next_job" => true} = args
       ) do
    # Schedule a new job with the timestamp of the earliest data point only if
    # arguments specify that it should be done.
    # The historical worker executes 2 types of jobs:
    #
    # 1. Daily jobs, scheduled by a cron job. They need only to get the previous day
    #    of data and do not schedule any more historical scrapes.
    # 2. Once deployed, a historical run is manually started. It will schedule
    #    a job with `schedule_next_job` set to true. This will in turn lead to
    #    scarping the full historical data for that market/instrument
    job_args =
      %{
        "market" => args["market"],
        "instrument" => args["instrument"],
        "schedule_next_job" => true,
        "timestamp" => min_timestamp,
        "limit" => @limit
      }
      |> Sanbase.Cryptocompare.OpenInterest.HistoricalWorker.new()

    case Oban.insert(@oban_conf_name, job_args) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp maybe_schedule_next_job(_min_timestamp, _args), do: :ok

  defp export_data(data) do
    data = Enum.map(data, &to_json_kv_tuple/1)
    topic = Config.module_get!(Sanbase.KafkaExporter, @topic)

    Sanbase.KafkaExporter.send_data_to_topic_from_current_process(data, topic)
  end

  defp to_json_kv_tuple(point) do
    point
    |> OHLCOpenInterestPoint.new()
    |> OHLCOpenInterestPoint.json_kv_tuple()
  end

  defp api_key(), do: Config.module_get(Sanbase.Cryptocompare, :api_key)
end
