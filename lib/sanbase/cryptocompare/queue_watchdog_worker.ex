defmodule Sanbase.Cryptocompare.QueueWatchdogWorker do
  @moduledoc ~s"""
  Self-healing watchdog for the Cryptocompare historical scraper queues.

  When a rate limit is hit, the historical queue is paused and a single
  scheduled `resume` job is responsible for resuming it. That single-shot
  resume can be lost:

  - the resume signal is delivered via the Oban notifier and is dropped if the
    notifier connection is down at that moment;
  - a queue producer that crashes is restarted with the config state, which is
    `paused: true`;
  - the resume job insert can be discarded by the uniqueness constraint in a
    narrow race with an executing resume job.

  Any of these leaves the queue paused forever and the exporter silently stops
  until the pod is restarted. This worker runs periodically via Oban cron and
  resumes any enabled queue that is paused without a pending resume job.

  See docs/cryptocompare-queue-pause-resume.md for the full design rationale.
  """
  use Oban.Worker, queue: :cryptocompare_watchdog_queue, max_attempts: 3

  import Ecto.Query

  require Logger

  # The historical workers expose historical_scheduler/0 and
  # pause_resume_worker/0 — the same callbacks Handler.handle_rate_limit/2 uses.
  @historical_workers [
    Sanbase.Cryptocompare.Price.HistoricalWorker,
    Sanbase.Cryptocompare.OpenInterest.HistoricalWorker,
    Sanbase.Cryptocompare.FundingRate.HistoricalWorker
  ]

  # A resume job in any of these states either will run or is running right
  # now, so the watchdog does not need to interfere.
  @resume_job_alive_states ~w[available scheduled executing retryable]

  @impl Oban.Worker
  def perform(_job) do
    Enum.each(@historical_workers, &resume_if_stuck/1)
    :ok
  end

  defp resume_if_stuck(historical_worker) do
    scheduler = historical_worker.historical_scheduler()

    # The queues start paused and are resumed on boot only when enabled, so a
    # paused queue of a disabled scheduler is intentional and must stay paused.
    with true <- scheduler.enabled?(),
         %{paused: true} <- Oban.check_queue(scheduler.conf_name(), queue: scheduler.queue()),
         false <-
           pending_resume_job_exists?(
             scheduler.conf_name(),
             historical_worker.pause_resume_worker()
           ) do
      Logger.warning(
        "[Cryptocompare Watchdog] Queue #{scheduler.queue()} is paused and has no " <>
          "pending resume job. Resuming it."
      )

      scheduler.resume()
    else
      _ -> :ok
    end
  end

  @doc false
  def pending_resume_job_exists?(oban_conf_name, pause_resume_worker) do
    worker_name = Oban.Worker.to_string(pause_resume_worker)

    query =
      from(j in Oban.Job,
        where:
          j.worker == ^worker_name and
            j.state in ^@resume_job_alive_states and
            fragment("?->>'type' = 'resume'", j.args)
      )

    # Oban.Repo injects the instance's repo and prefix — on prod the oban_jobs
    # table lives in the sanbase2 schema, not in public.
    oban_conf_name |> Oban.config() |> Oban.Repo.exists?(query)
  end
end
