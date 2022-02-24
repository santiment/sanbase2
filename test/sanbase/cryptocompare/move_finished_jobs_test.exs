defmodule Sanbase.Cryptocompare.MoveFinishedJobsTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2]
  import Sanbase.Cryptocompare.HistoricalDataStub, only: [http_call_data: 3]

  setup do
    Sanbase.InMemoryKafka.Producer.clear_state()
    project = insert(:random_erc20_project)

    mapping =
      insert(:source_slug_mapping,
        source: "cryptocompare",
        slug: project.ticker,
        project_id: project.id
      )

    %{
      project: project,
      project_cpc_name: mapping.slug,
      base_asset: mapping.slug,
      quote_asset: "USD"
    }
  end

  test "move finished jobs", context do
    %{base_asset: base_asset, quote_asset: quote_asset} = context
    from = ~D[2021-01-01]
    to = ~D[2021-01-10]

    Sanbase.Cryptocompare.HistoricalScheduler.add_jobs(base_asset, quote_asset, from, to)

    Sanbase.Mock.prepare_mock2(&HTTPoison.get/3, http_call_data(base_asset, quote_asset, from))
    |> Sanbase.Mock.run_with_mocks(fn ->
      Sanbase.Cryptocompare.HistoricalScheduler.resume()

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 10, failure: 0} =
               Oban.drain_queue(Sanbase.Cryptocompare.HistoricalWorker.conf_name(),
                 queue: Sanbase.Cryptocompare.HistoricalWorker.queue()
               )

      # Move 6 of the finished jobs to the finished queue
      assert {:ok, 6} = Sanbase.Cryptocompare.Jobs.move_finished_jobs(iterations: 2, limit: 3)

      # Check that 4 of the jobs are still not moved
      assert {:ok, %Postgrex.Result{rows: [[4]]}} =
               Ecto.Adapters.SQL.query(
                 Sanbase.Repo,
                 "select count(*) from oban_jobs where completed_at is not null"
               )

      # Check that 6 of the jobs are moved
      assert {:ok, %Postgrex.Result{rows: [[6]]}} =
               Ecto.Adapters.SQL.query(
                 Sanbase.Repo,
                 "select count(*) from finished_oban_jobs where completed_at is not null"
               )

      # Check that the get_pair_dates properly checks both tables
      dates =
        Sanbase.Cryptocompare.HistoricalScheduler.get_pair_dates(
          base_asset,
          quote_asset,
          from,
          to
        )

      assert generate_dates_inclusive(from, to) |> Enum.sort() == dates |> Enum.sort()
    end)
  end
end
