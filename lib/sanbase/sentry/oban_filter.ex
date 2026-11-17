defmodule Sanbase.Sentry.ObanFilter do
  @moduledoc ~s"""
  Decide whether a failed Oban job attempt is reported to Sentry.

  Used as the `should_report_error_callback` of the Sentry Oban integration.

  By default every failed attempt is reported. The workers listed in
  `@final_attempt_only_workers` fail on transient errors that the next attempt
  usually gets past (e.g. a dropped ClickHouse connection), so for them only the
  final attempt is reported. Errors those workers can detect as deterministic
  cancel the job, and cancelled jobs are never reported by the integration.
  """

  @final_attempt_only_workers [Sanbase.Queries.RefreshWorker]

  @doc ~s"""
  Return true if the failed attempt of `job` run by `worker` should be reported.

  ## Examples

      iex> job = %Oban.Job{attempt: 1, max_attempts: 3}
      iex> Sanbase.Sentry.ObanFilter.report?(Sanbase.Queries.RefreshWorker, job)
      false

      iex> job = %Oban.Job{attempt: 3, max_attempts: 3}
      iex> Sanbase.Sentry.ObanFilter.report?(Sanbase.Queries.RefreshWorker, job)
      true
  """
  @spec report?(module() | nil, Oban.Job.t()) :: boolean()
  def report?(worker, %Oban.Job{attempt: attempt, max_attempts: max_attempts})
      when worker in @final_attempt_only_workers,
      do: attempt >= max_attempts

  def report?(_worker, _job), do: true
end
