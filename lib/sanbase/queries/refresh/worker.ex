defmodule Sanbase.Queries.RefreshWorker do
  use Oban.Worker,
    queue: :refresh_queries,
    max_attempts: 3

  alias Sanbase.Queries.Refresh

  @oban_conf_name :oban_web
  @one_day 24 * 60 * 60

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id, "query_id" => query_id}} = job) do
    # Schedule a new job to refresh the query on the first attempt
    scheduled_job = if job.attempt == 1, do: schedule_next_refresh(job), else: nil

    Refresh.refresh_query(query_id, user_id)
    |> maybe_remove_scheduled_job(scheduled_job)
  end

  # private

  defp schedule_next_refresh(%Oban.Job{args: args}) do
    next_refresh_in_seconds = args["next_refresh_in_seconds"] || @one_day
    data = new(args, schedule_in: next_refresh_in_seconds)
    Oban.insert!(@oban_conf_name, data)
  end

  defp maybe_remove_scheduled_job(result, nil), do: result

  defp maybe_remove_scheduled_job({:error, error_str}, scheduled_job) do
    if clickhouse_error?(error_str) and Sanbase.ClickhouseRepo.retryable_error?(error_str) do
      {:error, error_str}
    else
      Oban.cancel_job(@oban_conf_name, scheduled_job)
      {:error, error_str}
    end
  end

  defp maybe_remove_scheduled_job(result, _), do: result

  defp clickhouse_error?(error_str) do
    # Clickhouse errors returned from our ClickhouseRepo
    # start with "Cannot execute ClickHouse database query"
    String.contains?(error_str, "ClickHouse")
  end
end
