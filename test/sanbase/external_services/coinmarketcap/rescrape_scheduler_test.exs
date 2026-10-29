defmodule Sanbase.ExternalServices.Coinmarketcap.RescrapeSchedulerTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.{
    ScheduleRescrapePrice,
    RescrapeScheduler,
    PriceScrapingProgress
  }

  @moduletag capture_log: true

  setup do
    project =
      insert(:project, %{
        slug: "bitcoin",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "coinmarketcap", slug: "bitcoin"})
        ]
      })

    insert(:latest_cmc_data, %{coinmarketcap_id: "bitcoin", coinmarketcap_integer_id: 1})
    Sanbase.InMemoryKafka.Producer.clear_state()

    [project: project]
  end

  test "scrapes the interval day by day without touching the regular scraper", context do
    mock_cmc_success()

    {:ok, _} =
      PriceScrapingProgress.store_progress("bitcoin", "coinmarketcap", ~U[2026-10-21 05:14:06Z])

    srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00])

    run_scheduler()

    assert Enum.sort(requested_ranges()) == [
             {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
             {~U[2023-07-20 00:00:00Z], ~U[2023-07-21 00:00:00Z]},
             {~U[2023-07-21 00:00:00Z], ~U[2023-07-22 00:00:00Z]}
           ]

    assert %{status: :finished, progress_datetime: ~N[2023-07-22 00:00:00]} = reload(srp)
    assert Sanbase.InMemoryKafka.Producer.get_state() |> Map.get("asset_prices") != []

    assert PriceScrapingProgress.last_scraped("bitcoin", "coinmarketcap") ==
             ~U[2026-10-21 05:14:06Z]
  end

  test "resumes from the cursor and extends a short last interval to 1 hour", context do
    mock_cmc_success()
    srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:10:00])
    {:ok, _} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])

    run_scheduler()

    assert Enum.sort(requested_ranges()) == [
             {~U[2023-07-20 00:00:00Z], ~U[2023-07-21 00:00:00Z]},
             {~U[2023-07-20 23:10:00Z], ~U[2023-07-21 00:10:00Z]}
           ]

    assert %{status: :finished} = reload(srp)
  end

  test "skips cancelled rescrapes and fails the ones without a coinmarketcap id", context do
    mock_cmc_success()
    cancelled = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])
    {:ok, _} = ScheduleRescrapePrice.cancel(cancelled)

    no_cmc_id =
      create_rescrape(insert(:random_project), ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

    run_scheduler()

    assert requested_ranges() == []
    assert %{status: :failed, last_error: "" <> error} = reload(no_cmc_id)
    assert error =~ "no coinmarketcap integer id"
  end

  describe "errors" do
    test "a failed day is retried from the cursor", context do
      # The first request fails, all the next ones succeed
      {:ok, counter} = Agent.start_link(fn -> 0 end)
      body = File.read!(Path.join(__DIR__, "data/btc_web_api_success2.json"))

      mock_cmc(fn ->
        case Agent.get_and_update(counter, &{&1, &1 + 1}) do
          0 -> %Tesla.Env{status: 500, body: "boom"}
          _ -> %Tesla.Env{status: 200, body: body}
        end
      end)

      srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_concurrency: 1)

      assert %{status: :finished, last_error: nil} = reload(srp)

      assert requested_ranges() == [
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-20 00:00:00Z], ~U[2023-07-21 00:00:00Z]}
             ]
    end

    test "after too many failures the rescrape is marked as failed", context do
      mock_cmc(fn -> %Tesla.Env{status: 500, body: "boom"} end)

      srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_failures: 3)

      assert %{status: :failed, progress_datetime: nil, last_error: "" <> error} = reload(srp)
      assert error =~ "Status: 500"
    end

    test "a crash while fetching is handled as an error", context do
      mock_cmc(fn -> exit(:boom) end)

      srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_failures: 1)

      assert %{status: :failed, last_error: "" <> error} = reload(srp)
      assert error =~ "exited"
    end
  end

  describe "priority" do
    test "the rescrape with the highest priority is progressed first", context do
      mock_cmc_success()

      ethereum =
        insert(:project, %{
          slug: "ethereum",
          source_slug_mappings: [
            build(:source_slug_mapping, %{source: "coinmarketcap", slug: "ethereum"})
          ]
        })

      insert(:latest_cmc_data, %{coinmarketcap_id: "ethereum", coinmarketcap_integer_id: 1027})

      create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00], :low)
      create_rescrape(ethereum, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00], :high)

      run_scheduler(max_concurrency: 1)

      assert requested_cmc_ids() == [1027, 1027, 1027, 1, 1, 1]
    end
  end

  # Run the scheduler until there is nothing left to fetch
  defp run_scheduler(opts \\ []) do
    opts =
      Keyword.merge(
        [enabled?: true, notify: self(), retry_after_ms: 0, refresh_interval_ms: 60_000],
        opts
      )

    start_supervised!({RescrapeScheduler, opts})
    assert_receive {:rescrape_scheduler, :idle}, 5_000
  end

  defp create_rescrape(project, from, to, priority \\ :normal) do
    {:ok, srp} =
      ScheduleRescrapePrice.create(%{
        project_id: project.id,
        from: from,
        to: to,
        priority: priority
      })

    srp
  end

  defp reload(srp), do: Sanbase.Repo.get!(ScheduleRescrapePrice, srp.id)

  defp mock_cmc_success() do
    body = File.read!(Path.join(__DIR__, "data/btc_web_api_success2.json"))
    mock_cmc(fn -> %Tesla.Env{status: 200, body: body} end)
  end

  # The requests are made by tasks started by the scheduler, so the mock is global
  defp mock_cmc(response_fun) do
    test_pid = self()

    Tesla.Mock.mock_global(fn %{method: :get, url: url} ->
      send(test_pid, {:cmc_request, url})
      response_fun.()
    end)
  end

  defp requested_urls(acc \\ []) do
    receive do
      {:cmc_request, url} -> requested_urls([url | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  # Up to 2 days of a rescrape are fetched in parallel, so the order of the
  # requests is deterministic only with max_concurrency: 1
  defp requested_ranges() do
    Enum.map(requested_urls(), fn url ->
      [_, from, to] = Regex.run(~r/range=(\d+)~(\d+)/, url)

      {DateTime.from_unix!(String.to_integer(from)), DateTime.from_unix!(String.to_integer(to))}
    end)
  end

  defp requested_cmc_ids() do
    Enum.map(requested_urls(), fn url ->
      [_, id] = Regex.run(~r/id=(\d+)/, url)
      String.to_integer(id)
    end)
  end
end
