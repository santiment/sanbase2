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
    query = """
    WITH finished_job_ids_cte AS (
      SELECT id from oban_jobs
      WHERE queue = '#{queue}' AND completed_at IS NOT NULL
      LIMIT #{limit}
    ),
    moved_rows AS (
      DELETE FROM oban_jobs a
      WHERE a.id IN (SELECT id FROM finished_job_ids_cte)
      RETURNING a.queue, a.worker, a.args, a.inserted_at, a.completed_at
    )
    INSERT INTO finished_oban_jobs(queue, worker, args, inserted_at, completed_at)
    SELECT * FROM moved_rows;
    """

    # Interpolate the query parameters instead of using a prepared statement.
    # Providing the params will result in the error:
    # `cannot insert multiple commands into a prepared statement`
    {:ok, %{num_rows: num_rows}} = Sanbase.Repo.query(query)

    {:ok, num_rows}
  end
end
