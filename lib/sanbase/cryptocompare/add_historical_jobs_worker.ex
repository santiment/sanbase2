defmodule Sanbase.Cryptocompare.AddHistoricalJobsWorker do
  use Oban.Worker, queue: :cryptocompare_historical_add_jobs_queue

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "schedule_historical_price_jobs"}}) do
    Logger.info("[Cryptocompare.AddHistoricalJobsWorker] Start adding historical price jobs.")

    Sanbase.Cryptocompare.Price.CCCAGGPairData.schedule_previous_day_jobs()

    Logger.info("[Cryptocompare.AddHistoricalJobsWorker] Finished adding historical price jobs.")

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "schedule_historical_open_interest_jobs"}
      }) do
    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Start adding historical open interest jobs."
    )

    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.schedule_previous_day_jobs()

    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Finished adding historical open interest jobs."
    )

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "schedule_historical_funding_rate_jobs"}
      }) do
    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Start adding historical funding rate jobs."
    )

    Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.schedule_previous_day_jobs()

    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Finished adding historical funding rate jobs."
    )

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)

  @impl Worker
  def backoff(%Job{attempt: attempt}) do
    # Use a linear backoff algorithm when scheduling jobs
    # This is so all the attempts can be made on the same day without
    # waiting too much. The max_attempts is also changed to 10
    300 * attempt
  end
end
