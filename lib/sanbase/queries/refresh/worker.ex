defmodule Sanbase.Queries.RefreshWorker do
  use Oban.Worker,
    queue: :refresh_queries,
    max_attempts: 3

  require Logger

  alias Sanbase.ClickhouseRepo
  alias Sanbase.Queries.Refresh

  @oban_conf_name :oban_web
  @one_day 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "query_id" => query_id}} = job) do
    Sanbase.Sentry.ObanTags.put_job_context(job)

    # Schedule a new job to refresh the query on the first attempt
    scheduled_job = if job.attempt == 1, do: schedule_next_refresh(job), else: nil

    Refresh.refresh_query(query_id, user_id)
    |> handle_result(job, query_id, user_id)
    |> maybe_remove_scheduled_job(scheduled_job)
  end

  # private

  defp handle_result({:error, error}, %Oban.Job{} = job, query_id, user_id) do
    error_str = error_to_string(error)

    Logger.warning(
      "[Queries.RefreshWorker] Failed to refresh query_id=#{query_id} user_id=#{user_id} " <>
        "(oban_job_id=#{job.id}, attempt=#{job.attempt}/#{job.max_attempts}): #{error_str}"
    )

    error_msg = "Failed to refresh query_id=#{query_id} user_id=#{user_id}. Reason: #{error_str}"

    if deterministic_error?(error_str), do: {:cancel, error_msg}, else: {:error, error_msg}
  end

  defp handle_result(result, _job, _query_id, _user_id), do: result

  defp error_to_string(error) when is_binary(error), do: error
  defp error_to_string(%{__exception__: true} = error), do: Exception.message(error)
  defp error_to_string(error), do: inspect(error)

  defp schedule_next_refresh(%Oban.Job{args: args}) do
    next_refresh_in_seconds = args["next_refresh_in_seconds"] || @one_day
    data = new(args, schedule_in: next_refresh_in_seconds)
    Oban.insert!(@oban_conf_name, data)
  end

  defp maybe_remove_scheduled_job(result, nil), do: result

  defp maybe_remove_scheduled_job({:cancel, _} = result, scheduled_job) do
    Oban.cancel_job(@oban_conf_name, scheduled_job)
    result
  end

  defp maybe_remove_scheduled_job(result, _), do: result

  @deterministic_errors [
    "Query does not exist or you don't have access to it.",
    "Cannot fetch the user with id"
  ]

  # ClickHouse error codes caused by load or the network; every other code is a query error
  @transient_clickhouse_error_codes ~w[
    TIMEOUT_EXCEEDED
    TOO_MANY_SIMULTANEOUS_QUERIES
    NETWORK_ERROR
    SOCKET_TIMEOUT
    QUERY_WAS_CANCELLED
    ALL_CONNECTION_TRIES_FAILED
  ]

  defp deterministic_error?(error_str) do
    code = ClickhouseRepo.error_code(error_str)

    Enum.any?(@deterministic_errors, &String.contains?(error_str, &1)) or
      (code != nil and code not in @transient_clickhouse_error_codes)
  end
end
