defmodule Sanbase.Cryptocompare.FundingRate.HistoricalWorker do
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
  @queue :cryptocompare_funding_rate_historical_jobs_queue
  use Oban.Worker,
    queue: @queue,
    unique: [period: 60 * 86_400]

  alias Sanbase.Utils.Config
  alias Sanbase.Cryptocompare.FundingRatePoint
  alias Sanbase.Cryptocompare.ExporterProgress
  alias Sanbase.Cryptocompare.Handler

  require Logger

  @url "https://data-api.cryptocompare.com/futures/v1/historical/funding-rate/minutes"
  @limit 2000
  @oban_conf_name :oban_scrapers
  @topic :funding_rate_topic

  def queue(), do: @queue
  def conf_name(), do: @oban_conf_name
  def default_limit(), do: @limit

  def pause_resume_worker(),
    do: Sanbase.Cryptocompare.FundingRate.PauseResumeWorker

  def historical_scheduler(),
    do: Sanbase.Cryptocompare.FundingRate.HistoricalScheduler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    %{"market" => market, "instrument" => instrument, "timestamp" => timestamp} = args

    limit = Map.get(args, "limit", @limit)

    case get_data(market, instrument, limit, timestamp) do
      {:ok, _, []} ->
        :ok

      {:ok, min_timestamp, data} ->
        :ok = export_data(data)

        {min, max} = Enum.min_max_by(data, & &1.timestamp)
        :ok = maybe_schedule_next_job(min_timestamp, args)

        {:ok, _} =
          ExporterProgress.create_or_update(
            "#{market}_#{instrument}",
            to_string(@queue),
            min.timestamp,
            max.timestamp
          )

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

    case Handler.execute_http_request(@url, query_params) do
      {:ok, %{status_code: 200} = http_response} ->
        Sanbase.Cryptocompare.Handler.handle_http_response(http_response,
          module: __MODULE__,
          timestamps_key: "#{market}_#{instrument}",
          process_function: &process_json_response/1,
          remove_known_timestamps: true
        )

      {:ok, %{status_code: 404}} ->
        # The error is No HOUR entries available on or before <timestamp>
        {:error, :first_timestamp_reached}

      {:error, error} ->
        {:error, error}
    end
  end

  defp process_json_response(http_response_body) do
    data =
      http_response_body
      |> Jason.decode!()
      |> get_in(["Data"])
      |> Enum.map(fn map ->
        %{
          timestamp: map["TIMESTAMP"],
          market: map["MARKET"],
          instrument: map["INSTRUMENT"],
          mapped_instrument: map["MAPPED_INSTRUMENT"],
          quote_currency: map["QUOTE_CURRENCY"],
          settlement_currency: map["SETTLEMENT_CURRENCY"],
          contract_currency: map["CONTRACT_CURRENCY"],
          close: map["CLOSE"]
        }
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
      |> Sanbase.Cryptocompare.FundingRate.HistoricalWorker.new()

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
    |> FundingRatePoint.new()
    |> FundingRatePoint.json_kv_tuple()
  end
end
