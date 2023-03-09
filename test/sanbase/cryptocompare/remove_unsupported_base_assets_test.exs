defmodule Sanbase.Cryptocompare.RemoveUnsupportedBaseAssetsTest do
  use Sanbase.DataCase
  use Oban.Testing, repo: Sanbase.Repo

  import Sanbase.Factory

  alias Sanbase.Project

  setup do
    [p1, p2, p3, p4] = projects = for _ <- 1..4, do: insert(:random_erc20_project)

    for p <- projects do
      insert(:source_slug_mapping, source: "cryptocompare", slug: p.ticker, project_id: p.id)
    end

    %{p1: p1, p2: p2, p3: p3, p4: p4}
  end

  test "remove jobs for unsupported assets", context do
    %{p1: p1, p2: p2, p3: p3, p4: p4} = context
    from = ~D[2021-01-01]
    to = ~D[2021-01-10]

    for p <- [p1, p2, p3, p4] do
      Sanbase.Cryptocompare.Price.HistoricalScheduler.add_jobs(p.ticker, "USD", from, to)
    end

    # Check that all 40 jobs and 4 different base assets are present
    assert {:ok, %{rows: [[40]]}} =
             Ecto.Adapters.SQL.query(Sanbase.Repo, "SELECT count(*) FROM oban_jobs;", [])

    {:ok, base_assets} =
      Sanbase.Cryptocompare.Jobs.get_oban_jobs_base_assets("cryptocompare_historical_jobs_queue")

    assert [p1.ticker, p2.ticker, p3.ticker, p4.ticker] |> Enum.sort() ==
             base_assets |> Enum.sort()

    # Remove two of the mappings making those 2 no longer supported
    assert {1, nil} = Project.SourceSlugMapping.remove(p1.id, "cryptocompare")
    assert {1, nil} = Project.SourceSlugMapping.remove(p4.id, "cryptocompare")

    # Remove the unsupported base assets and test that the jobs are removed
    Sanbase.Cryptocompare.Jobs.remove_oban_jobs_unsupported_assets()

    assert {:ok, %{rows: [[20]]}} =
             Ecto.Adapters.SQL.query(Sanbase.Repo, "SELECT count(*) FROM oban_jobs;", [])

    {:ok, base_assets} =
      Sanbase.Cryptocompare.Jobs.get_oban_jobs_base_assets("cryptocompare_historical_jobs_queue")

    assert [p2.ticker, p3.ticker] |> Enum.sort() ==
             base_assets |> Enum.sort()
  end
end
