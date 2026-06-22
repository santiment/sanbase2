defmodule Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker do
  # NOTE: `states` must exclude :completed. With the default states a *completed*
  # resume job blocks enqueueing a new one for `period` seconds, so if the queue
  # is paused again within that window no resume is scheduled and the queue stays
  # paused forever. Keeping only the non-terminal states still prevents duplicate
  # pending resumes while always allowing a fresh resume after one finishes.
  use Oban.Worker,
    queue: :cryptocompare_open_interest_historical_jobs_pause_resume_queue,
    unique: [period: 60, states: [:available, :scheduled, :executing, :retryable]]

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
