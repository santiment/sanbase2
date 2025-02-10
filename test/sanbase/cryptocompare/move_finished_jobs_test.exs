defmodule Sanbase.Cryptocompare.MoveFinishedJobsTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Cryptocompare.HistoricalDataStub, only: [ohlcv_price_data: 3]
  import Sanbase.DateTimeUtils, only: [generate_dates_inclusive: 2]
  import Sanbase.Factory

  alias Ecto.Adapters.SQL
  alias Sanbase.Cryptocompare.Price.HistoricalScheduler
  alias Sanbase.Cryptocompare.Price.HistoricalWorker

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

    HistoricalScheduler.add_jobs(base_asset, quote_asset, from, to)

    (&HTTPoison.get/3)
    |> Sanbase.Mock.prepare_mock2(ohlcv_price_data(base_asset, quote_asset, from))
    |> Sanbase.Mock.run_with_mocks(fn ->
      HistoricalScheduler.resume()

      # Drain the queue, synchronously executing all the jobs in the current process
      assert %{success: 10, failure: 0} =
               Oban.drain_queue(HistoricalWorker.conf_name(),
                 queue: HistoricalWorker.queue()
               )

      # Move 6 of the finished jobs to the finished queue
      assert {:ok, 6} = Sanbase.Cryptocompare.Jobs.move_finished_jobs(iterations: 2, limit: 3)

      # Check that 4 of the jobs are still not moved
      assert {:ok, %Postgrex.Result{rows: [[4]]}} =
               SQL.query(
                 Sanbase.Repo,
                 "select count(*) from oban_jobs where completed_at is not null"
               )

      # Check that 6 of the jobs are moved
      assert {:ok, %Postgrex.Result{rows: [[6]]}} =
               SQL.query(
                 Sanbase.Repo,
                 "select count(*) from finished_oban_jobs where completed_at is not null"
               )

      # Check that the get_pair_dates properly checks both tables
      dates =
        HistoricalScheduler.get_pair_dates(
          base_asset,
          quote_asset,
          from,
          to
        )

      assert from |> generate_dates_inclusive(to) |> Enum.sort() == Enum.sort(dates)
    end)
  end
end
