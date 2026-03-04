defmodule Sanbase.Cryptocompare.AddHistoricalJobsWorker do
  @moduledoc ~s"""
  Oban worker that schedules historical data fetching jobs for Cryptocompare.

  Handles three types of scheduling:
  - Price: schedules daily OHLCV price jobs via CCCAGGPairData
  - Open Interest: schedules hourly OI jobs and daily backfills
  - Funding Rate: schedules hourly FR jobs and daily backfills

  The backfill job runs daily and re-schedules jobs for the past 7 days
  to fill any gaps caused by rate limiting, API outages, or transient errors.
  """
  use Oban.Worker, queue: :cryptocompare_historical_add_jobs_queue

  require Logger

  @backfill_days 7

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

    prod_env? = deployment_env() == "prod"
    hour = DateTime.utc_now().hour

    # On prod we add a job every time this triggers. On stage we add a job every 3 hours.
    # This is done in order to reduce the overall API calls amount.
    if prod_env? or rem(hour, 3) == 0 do
      # The limit is set to a higher value so it can account for delays in the scheduler.
      # The scheduler runs every 1 hour.
      Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.schedule_jobs(limit: 500)
    end

    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Finished adding historical funding rate jobs."
    )

    :ok
  end

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"type" => "schedule_derivatives_backfill_jobs"}
      }) do
    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Start scheduling derivatives backfill jobs " <>
        "for the past #{@backfill_days} days."
    )

    # Schedule previous day jobs for each of the last N days.
    # This fills gaps caused by rate limiting, API outages, or transient failures.
    # Oban uniqueness prevents duplicate jobs — completed jobs allow re-insertion,
    # so only genuinely missing windows get new jobs.
    for days_back <- 1..@backfill_days do
      datetime = DateTime.utc_now() |> DateTime.add(-days_back * 86_400)

      Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.schedule_previous_day_jobs(
        datetime: datetime,
        limit: 2000
      )

      Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.schedule_previous_day_jobs(
        datetime: datetime,
        limit: 2000
      )
    end

    Logger.info(
      "[Cryptocompare.AddHistoricalJobsWorker] Finished scheduling derivatives backfill jobs."
    )

    :ok
  end

  @impl Oban.Worker
  def timeout(_job), do: :timer.minutes(60)

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    # Use a linear backoff algorithm when scheduling jobs
    # This is so all the attempts can be made on the same day without
    # waiting too much. The max_attempts is also changed to 10
    300 * attempt
  end

  def deployment_env() do
    Sanbase.Utils.Config.module_get(Sanbase, :deployment_env)
  end
end
