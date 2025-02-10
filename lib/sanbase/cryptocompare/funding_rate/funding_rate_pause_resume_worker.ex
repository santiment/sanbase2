defmodule Sanbase.Cryptocompare.FundingRate.PauseResumeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :cryptocompare_funding_rate_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  alias Sanbase.Cryptocompare.FundingRate.HistoricalScheduler

  def perform(%{"action" => "resume"}) do
    HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    HistoricalScheduler.pause()
  end
end
