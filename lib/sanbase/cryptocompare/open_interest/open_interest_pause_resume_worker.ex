defmodule Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_open_interest_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "resume"}}) do
    Logger.info("[Cryptocompare OpenInterest] Resuming historical jobs queue after rate limit.")
    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.resume()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "pause"}}) do
    Logger.info("[Cryptocompare OpenInterest] Pausing historical jobs queue.")
    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.pause()
  end
end
