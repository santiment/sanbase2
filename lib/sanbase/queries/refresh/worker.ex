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
    if job.attempt == 1, do: schedule_next_refresh(job)

    Refresh.refresh_query(query_id, user_id)
  end

  # private

  defp schedule_next_refresh(%Oban.Job{args: args}) do
    next_refresh_in_seconds = args["next_refresh_in_seconds"] || @one_day
    data = new(args, schedule_in: next_refresh_in_seconds)
    Oban.insert!(@oban_conf_name, data)
  end
end
