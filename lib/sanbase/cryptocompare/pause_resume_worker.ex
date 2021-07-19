defmodule Sanbase.Cryptocompare.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  def perform(%{"action" => "resume"}) do
    Sanbase.Cryptocompare.HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    Sanbase.Cryptocompare.HistoricalScheduler.pause()
  end
end
