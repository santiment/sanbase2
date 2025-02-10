defmodule Sanbase.Queries.RefreshSchedulerWorker do
  @moduledoc false
  use Oban.Worker,
    queue: :refresh_queries,
    max_attempts: 3

  alias Sanbase.Queries.Refresh

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"user_id" => user_id}}) do
    Refresh.refresh_all_user_queries(user_id)
  end
end
