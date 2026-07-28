defmodule Sanbase.Cryptocompare.Price.PauseResumeWorker do
  # NOTE: `states` must exclude :completed. With the default states a *completed*
  # resume job blocks enqueueing a new one for `period` seconds, so if the queue
  # is paused again within that window no resume is scheduled and the queue stays
  # paused forever. Keeping only the non-terminal states still prevents duplicate
  # pending resumes while always allowing a fresh resume after one finishes.
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_pause_resume_queue,
    unique: [period: 60, states: :incomplete]

  require Logger

  alias Sanbase.Cryptocompare.Handler
  alias Sanbase.Cryptocompare.Price.HistoricalScheduler

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "resume"}}) do
    Logger.info("[Cryptocompare Price] Resuming historical jobs queue after rate limit.")
    Handler.resume_and_verify(HistoricalScheduler)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"type" => "pause"}}) do
    Logger.info("[Cryptocompare Price] Pausing historical jobs queue.")
    HistoricalScheduler.pause()
  end
end
