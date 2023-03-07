defmodule Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_open_interest_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  def perform(%{"action" => "resume"}) do
    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler.pause()
  end
end
