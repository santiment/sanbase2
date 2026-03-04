defmodule Sanbase.Cryptocompare.FundingRate.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_funding_rate_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "resume"}}) do
    Logger.info("[Cryptocompare FundingRate] Resuming historical jobs queue after rate limit.")
    Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.resume()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "pause"}}) do
    Logger.info("[Cryptocompare FundingRate] Pausing historical jobs queue.")
    Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.pause()
  end
end
