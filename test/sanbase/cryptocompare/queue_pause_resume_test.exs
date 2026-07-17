defmodule Sanbase.Cryptocompare.QueuePauseResumeTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Ecto.Query
  import ExUnit.CaptureLog

  alias Sanbase.Cryptocompare.Handler
  alias Sanbase.Cryptocompare.OpenInterest
  alias Sanbase.Cryptocompare.QueueWatchdogWorker

  @conf_name :oban_scrapers

  describe "Handler.schedule_resume_job/2" do
    test "schedules a resume job" do
      assert :ok = Handler.schedule_resume_job(OpenInterest.HistoricalWorker, 60)

      assert [job] = all_enqueued(worker: OpenInterest.PauseResumeWorker)
      assert job.args == %{"type" => "resume"}
      assert job.state == "scheduled"
    end

    test "a pending resume job absorbs the duplicate insert" do
      :ok = Handler.schedule_resume_job(OpenInterest.HistoricalWorker, 60)
      :ok = Handler.schedule_resume_job(OpenInterest.HistoricalWorker, 60)

      # The second insert conflicts with the scheduled job, which will still
      # run in the future, so no new job and no immediate resume are needed.
      assert [_job] = all_enqueued(worker: OpenInterest.PauseResumeWorker)
    end

    test "conflict with an executing resume job triggers an immediate resume" do
      :ok = Handler.schedule_resume_job(OpenInterest.HistoricalWorker, 60)

      # Simulate the poison race: the pending resume job is currently executing,
      # so it may have already resumed the queue before the new pause landed.
      from(j in Oban.Job,
        where: j.worker == "Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker"
      )
      |> Sanbase.Repo.update_all(set: [state: "executing"])

      log =
        capture_log(fn ->
          assert :ok = Handler.schedule_resume_job(OpenInterest.HistoricalWorker, 60)
        end)

      assert log =~ "Resume job insert conflicted with a resume job in state executing"
      assert log =~ "Resuming queue immediately"
    end
  end

  describe "QueueWatchdogWorker" do
    test "perform/1 returns :ok" do
      assert :ok = perform_job(QueueWatchdogWorker, %{})
    end

    test "pending_resume_job_exists?/2 sees only pending resume jobs" do
      refute QueueWatchdogWorker.pending_resume_job_exists?(
               @conf_name,
               OpenInterest.PauseResumeWorker
             )

      {:ok, _} =
        Oban.insert(
          @conf_name,
          OpenInterest.PauseResumeWorker.new(%{"type" => "resume"}, schedule_in: 60)
        )

      assert QueueWatchdogWorker.pending_resume_job_exists?(
               @conf_name,
               OpenInterest.PauseResumeWorker
             )

      from(j in Oban.Job,
        where: j.worker == "Sanbase.Cryptocompare.OpenInterest.PauseResumeWorker"
      )
      |> Sanbase.Repo.update_all(set: [state: "completed"])

      refute QueueWatchdogWorker.pending_resume_job_exists?(
               @conf_name,
               OpenInterest.PauseResumeWorker
             )
    end
  end
end
