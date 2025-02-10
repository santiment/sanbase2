defmodule Sanbase.Cryptocompare.Price.PauseResumeWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :cryptocompare_historical_jobs_pause_resume_queue,
    unique: [period: 60]

  alias Sanbase.Cryptocompare.Price.HistoricalScheduler

  def perform(%{"action" => "resume"}) do
    HistoricalScheduler.resume()
  end

  def perform(%{"action" => "pause"}) do
    HistoricalScheduler.pause()
  end
end
