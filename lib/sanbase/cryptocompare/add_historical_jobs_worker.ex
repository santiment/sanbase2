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

    prod_env? = deployment_env() == "prod"
    hour = DateTime.utc_now().hour

    # On prod we add a job every time this triggers. On stage we add a job every 3 hours.
    # This is done in order to reduce the overall API calls amount.
    if prod_env? or rem(hour, 3) == 0 do
      # The limit is set to a higher value so it can account for delays in the scheduler.
      # The scheduler runs every 1 hour.
      Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.schedule_jobs(limit: 500)
    end

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

  def deployment_env() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
  end
end
