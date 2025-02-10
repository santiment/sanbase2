defmodule Sanbase.Cryptocompare.Jobs do
  @moduledoc false
  alias Ecto.Adapters.SQL
  alias Sanbase.Cryptocompare.FundingRate
  alias Sanbase.Cryptocompare.OpenInterest
  alias Sanbase.Cryptocompare.Price
  alias Sanbase.Project

  # Execute the function until the moved rows are 0 or up to 100 iterations.
  # The iterations are needed to avoid an infinite loop. If there is a task that
  # finishes one job every second we risk to always return 1 row and never finish
  # the job.

  def move_finished_jobs(opts \\ []) do
    queues =
      [price_queue(), open_interest_queue(), funding_rate_queue()] ++
        [
          "cryptocompare_historical_add_jobs_queue",
          "email_queue",
          "twitter_followers_migration_queue"
        ]

    queues = Enum.uniq(queues)

    for_result =
      for queue <- queues do
        do_move_finished_jobs(queue, opts)
      end

    Enum.reduce_while(for_result, {:ok, 0}, fn
      {:ok, count}, {:ok, acc} -> {:cont, {:ok, count + acc}}
      {:error, error}, _ -> {:halt, {:error, error}}
    end)
  end

  defp do_move_finished_jobs(queue, opts) do
    iterations = Keyword.get(opts, :iterations, 200)
    limit = Keyword.get(opts, :limit, 10_000)

    count =
      Enum.reduce_while(1..iterations, 0, fn _, rows_count_acc ->
        case do_move_completed_jobs(queue, limit) do
          {:ok, 0} -> {:halt, rows_count_acc}
          {:ok, rows_count} -> {:cont, rows_count + rows_count_acc}
        end
      end)

    {:ok, count}
  end

  def remove_oban_jobs_unsupported_assets do
    {:ok, oban_jobs_base_assets} = get_oban_jobs_base_assets(price_queue())

    supported_base_assets =
      "cryptocompare"
      |> Project.SourceSlugMapping.get_source_slug_mappings()
      |> Enum.map(&elem(&1, 0))

    unsupported_base_assets = oban_jobs_base_assets -- supported_base_assets

    Enum.map(unsupported_base_assets, fn base_asset ->
      {:ok, _} = delete_not_completed_base_asset_jobs(price_queue(), base_asset)
    end)
  end

  def get_oban_jobs_base_assets(queue) do
    query = """
    SELECT distinct(args->>'base_asset') FROM oban_jobs
    WHERE queue = $1 AND completed_at IS NULL
    """

    {:ok, %{rows: rows}} = SQL.query(Sanbase.Repo, query, [queue], timeout: 150_000)
    {:ok, List.flatten(rows)}
  end

  # Private functions

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

  defp delete_not_completed_base_asset_jobs(queue, base_asset) do
    query = """
    DELETE FROM oban_jobs
    WHERE queue = $1 AND args->>'base_asset' = $2 AND completed_at IS NULL;
    """

    {:ok, %{num_rows: num_rows}} =
      SQL.query(Sanbase.Repo, query, [queue, base_asset], timeout: 150_000)

    {:ok, %{num_rows: num_rows, base_asset: base_asset}}
  end

  defp price_queue, do: to_string(Price.HistoricalScheduler.queue())
  defp open_interest_queue, do: to_string(OpenInterest.HistoricalScheduler.queue())
  defp funding_rate_queue, do: to_string(FundingRate.HistoricalScheduler.queue())
end
