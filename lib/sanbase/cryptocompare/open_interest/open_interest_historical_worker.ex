queue = :cryptocompare_open_interest_historical_jobs_queue

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
  use Oban.Worker,
    queue: unquote(queue),
    max_attempts: 20,
    unique: [period: 60 * 86_400]

  alias Sanbase.Cryptocompare.ExporterProgress
  alias Sanbase.Cryptocompare.Handler
  alias Sanbase.Cryptocompare.OpenInterestPoint
  alias Sanbase.Utils.Config

  require Logger

  @queue queue
  @url "https://data-api.cryptocompare.com/futures/v1/historical/open-interest/minutes"
  @default_limit 2000
  @oban_conf_name :oban_scrapers
  @topic :open_interest_topic
  @topic_v2 :open_interest_topic_v2

  def queue, do: @queue
  def conf_name, do: @oban_conf_name
  def default_limit, do: @default_limit

  def pause_resume_worker, do: Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker

  def historical_scheduler, do: Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler

  @impl Oban.Worker
  def perform(%Oban.Job{args: args}) do
    args = Map.put_new(args, "version", "v1")

    %{
      "market" => market,
      "instrument" => instrument,
      "timestamp" => timestamp,
      "version" => version
    } = args

    exporter_progress_key =
      case version do
        "v1" -> "#{market}_#{instrument}"
        "v2" -> "#{market}_#{instrument}_v2"
      end

    opts = [
      market: market,
      instrument: instrument,
      limit: Map.get(args, "limit", @default_limit),
      timestamp: timestamp,
      queue: @queue,
      exporter_progress_key: exporter_progress_key,
      version: version
    ]

    case Handler.get_data(@url, &process_json_response/1, opts) do
      {:ok, min_timestamp, []} when is_integer(min_timestamp) ->
        :ok = maybe_schedule_next_job(min_timestamp, args)

      {:ok, _min_timestamp, []} ->
        :ok

      {:ok, min_timestamp, data} ->
        {:ok, _} = export_data_and_update_progress(data, min_timestamp, args)
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

  defp export_data_and_update_progress(data, min_timestamp, args) do
    :ok = export_data(data, args)

    {min, max} = Enum.min_max_by(data, & &1.timestamp)
    :ok = maybe_schedule_next_job(min_timestamp, args)

    exporter_progress_key =
      case args["version"] do
        "v1" -> "#{args["market"]}_#{args["instrument"]}"
        "v2" -> "#{args["market"]}_#{args["instrument"]}_v2"
      end

    {:ok, _} =
      ExporterProgress.create_or_update(
        exporter_progress_key,
        to_string(@queue),
        min.timestamp,
        max.timestamp
      )
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
          close_settlement: map["CLOSE_SETTLEMENT"],
          close_mark_price: map["CLOSE_MARK_PRICE"],
          close_quote: map["CLOSE_QUOTE"]
        }
      end)

    # Create a new job with `first_timetamp`
    {:ok, data}
  end

  defp maybe_schedule_next_job(min_timestamp, %{"schedule_next_job" => true} = args) do
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
      Sanbase.Cryptocompare.OpenInterest.HistoricalWorker.new(%{
        "market" => args["market"],
        "instrument" => args["instrument"],
        "schedule_next_job" => true,
        "timestamp" => min_timestamp,
        "limit" => args["limit"],
        "version" => args["version"]
      })

    case Oban.insert(@oban_conf_name, job_args) do
      {:ok, _} -> :ok
      error -> error
    end
  end

  defp maybe_schedule_next_job(_min_timestamp, _args), do: :ok

  defp export_data(data, args) do
    data = Enum.map(data, &to_json_kv_tuple/1)

    topic =
      case args["version"] do
        "v1" -> Config.module_get!(Sanbase.KafkaExporter, @topic)
        "v2" -> Config.module_get!(Sanbase.KafkaExporter, @topic_v2)
      end

    Sanbase.KafkaExporter.send_data_to_topic_from_current_process(data, topic)
  end

  defp to_json_kv_tuple(point) do
    point
    |> OpenInterestPoint.new()
    |> OpenInterestPoint.json_kv_tuple()
  end
end
