defmodule Sanbase.Cryptocompare.FundingRate.PauseResumeWorker do
  use Oban.Worker,
    queue: :cryptocompare_funding_rate_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  def perform(%{"action" => "resume"}) do
    Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    Sanbase.Cryptocompare.FundingRate.HistoricalScheduler.pause()
  end
end
