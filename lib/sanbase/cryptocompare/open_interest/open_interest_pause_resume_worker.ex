defmodule Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :cryptocompare_open_interest_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  alias Sanbase.Cryptocompare.OpenInterest.HistoricalScheduler

  def perform(%{"action" => "resume"}) do
    HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    HistoricalScheduler.pause()
  end
end
