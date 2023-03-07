defmodule Sanbase.Cryptocompare.Price.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  def perform(%{"action" => "resume"}) do
    Sanbase.Cryptocompare.Price.HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    Sanbase.Cryptocompare.Price.HistoricalScheduler.pause()
  end
end
