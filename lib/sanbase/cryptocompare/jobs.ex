defmodule Sanbase.Cryptocompare.Jobs do
  # Execute the function until the moved rows are 0 or up to 100 iterations.
  # The iterations are needed to avoid an infinite loop. If there is a task that
  # finishes one job every second we risk to always return 1 row and never finish
  # the job.
  def move_finished_jobs(opts \\ []) do
    iterations = Keyword.get(opts, :iterations, 200)
    limit = Keyword.get(opts, :limit, 10_000)

    count =
      1..iterations
      |> Enum.reduce_while(0, fn _, rows_count_acc ->
        case do_move_completed_jobs("cryptocompare_historical_jobs_queue", limit) do
          {:ok, 0} -> {:halt, rows_count_acc}
          {:ok, rows_count} -> {:cont, rows_count + rows_count_acc}
        end
      end)

    {:ok, count}
  end

  defp do_move_completed_jobs(queue, limit) do
    # Instead of deleting the records directly from the oban_jobs table, define
    # a CTE that selects the needed jobs first so we can put a `limit` on how
    # many can be done at once.
    # In a second CTE delete those records from the oban_jobs and return them,
    # so they can be used to be inserted into the `finished_oban_jobs` table.
    # Return the number of affected rows so when they become 0 we can
    query = "SELECT moveFinishedObanJobs($1, $2);"

    # The affected rows count is returned as a result of the function and should not
    # be taken from the `num_rows` field as it is always 1.
    {:ok, %{rows: [[affected_rows_count]]}} = Sanbase.Repo.query(query, [queue, limit])

    {:ok, affected_rows_count}
  end
end
