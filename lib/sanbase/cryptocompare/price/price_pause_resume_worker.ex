defmodule Sanbase.Cryptocompare.Price.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "resume"}}) do
    Logger.info("[Cryptocompare Price] Resuming historical jobs queue after rate limit.")
    Sanbase.Cryptocompare.Price.HistoricalScheduler.resume()
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "pause"}}) do
    Logger.info("[Cryptocompare Price] Pausing historical jobs queue.")
    Sanbase.Cryptocompare.Price.HistoricalScheduler.pause()
  end
end
