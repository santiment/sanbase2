defmodule Sanbase.Queries.RefreshWorker do
  use Oban.Worker,
    queue: :refresh_queries,
    max_attempts: 3

  require Logger

  alias Sanbase.Queries.Refresh

  @oban_conf_name :oban_web
  @one_day 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "query_id" => query_id}} = job) do
    # Make the query_id/user_id searchable Sentry tags in case the job fails
    Sanbase.Sentry.ObanTags.put_job_context(job)

    # Schedule a new job to refresh the query on the first attempt
    scheduled_job = if job.attempt == 1, do: schedule_next_refresh(job), else: nil

    Refresh.refresh_query(query_id, user_id)
    |> handle_result(job, query_id, user_id)
    |> maybe_remove_scheduled_job(scheduled_job)
  end

  # private

  # Attach the identifiers of the offending query to the error before it is
  # returned to Oban. The error tuple returned from here is what ends up in the
  # Oban.PerformError message that is reported to Sentry, so the query can be
  # located in postgres (`SELECT * FROM queries WHERE id = <query_id>`) directly
  # from the error title, without inspecting the job args.
  defp handle_result({:error, error}, %Oban.Job{} = job, query_id, user_id) do
    error_str = error_to_string(error)

    Logger.warning(
      "[Queries.RefreshWorker] Failed to refresh query_id=#{query_id} user_id=#{user_id} " <>
        "(oban_job_id=#{job.id}, attempt=#{job.attempt}/#{job.max_attempts}): #{error_str}"
    )

    {:error, "Failed to refresh query_id=#{query_id} user_id=#{user_id}. Reason: #{error_str}"}
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

  defp maybe_remove_scheduled_job({:error, error_str}, scheduled_job) do
    case retryable_error?(error_str) do
      true ->
        {:error, error_str}

      false ->
        Oban.cancel_job(@oban_conf_name, scheduled_job)
        {:error, error_str}
    end
  end

  defp maybe_remove_scheduled_job(result, _), do: result

  defp retryable_error?(error_str) do
    non_retryable_errors = [
      "(SYNTAX_ERROR)",
      "(ILLEGAL_TYPE_OF_ARGUMENT)",
      "(UNKNOWN_IDENTIFIER)",
      "(ACCESS_DENIED)",
      "(UNKNOWN_TABLE)",
      "(MEMORY_LIMIT_EXCEEDED)",
      "(AMBIGUOUS_COLUMN_NAME)",
      # The query or its owner is gone - there is nothing left to refresh, so the
      # daily chain must not be prolonged. Errors that the owner can still fix
      # (a {{key}} template without a matching parameter, for example) are kept
      # retryable on purpose, so the auto-refresh resumes on its own once fixed.
      "Query does not exist or you don't have access to it.",
      "Cannot fetch the user with id"
    ]

    has_non_retryable_error? =
      Enum.any?(non_retryable_errors, fn error -> String.contains?(error_str, error) end)

    not has_non_retryable_error?
  end
end
