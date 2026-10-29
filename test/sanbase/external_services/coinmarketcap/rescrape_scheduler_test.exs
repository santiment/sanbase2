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

  describe "executing a rescrape" do
    test "scrapes the interval day by day and finishes", context do
      mock_cmc_success()

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00])

      run_scheduler()

      assert Enum.sort(requested_ranges()) == [
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-20 00:00:00Z], ~U[2023-07-21 00:00:00Z]},
               {~U[2023-07-21 00:00:00Z], ~U[2023-07-22 00:00:00Z]}
             ]

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :finished
      assert srp.progress_datetime == ~N[2023-07-22 00:00:00]
      assert srp.started_at != nil
      assert srp.finished_at != nil

      prices = Sanbase.InMemoryKafka.Producer.get_state() |> Map.get("asset_prices")
      assert prices != []
    end

    test "does not touch the progress of the regular scraper", context do
      mock_cmc_success()

      {:ok, _} =
        PriceScrapingProgress.store_progress("bitcoin", "coinmarketcap", ~U[2026-10-21 05:14:06Z])

      {:ok, _srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-20 00:00:00])

      run_scheduler()

      assert PriceScrapingProgress.last_scraped("bitcoin", "coinmarketcap") ==
               ~U[2026-10-21 05:14:06Z]
    end

    test "resumes from the cursor", context do
      mock_cmc_success()

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00])

      {:ok, _} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-21 00:00:00])

      run_scheduler()

      assert requested_ranges() == [{~U[2023-07-21 00:00:00Z], ~U[2023-07-22 00:00:00Z]}]
    end

    test "a short last interval is extended to 1 hour", context do
      mock_cmc_success()

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-20 00:10:00])

      run_scheduler()

      assert Enum.sort(requested_ranges()) == [
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-19 23:10:00Z], ~U[2023-07-20 00:10:00Z]}
             ]

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :finished
      assert srp.progress_datetime == ~N[2023-07-20 00:10:00]
    end

    test "a day without price points does not end the rescrape", context do
      mock_cmc(fn -> %Tesla.Env{status: 200, body: Jason.encode!(empty_points_response())} end)

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler()

      assert length(requested_ranges()) == 2
      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.progress_datetime == ~N[2023-07-21 00:00:00]
      assert srp.status == :finished
    end

    test "a cancelled rescrape is not executed", context do
      mock_cmc_success()

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      {:ok, _} = ScheduleRescrapePrice.cancel(srp)

      run_scheduler()

      assert requested_ranges() == []
    end

    test "a project without a coinmarketcap integer id fails the rescrape" do
      project = insert(:random_project)

      {:ok, srp} = create_rescrape(project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler()

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :failed
      assert srp.last_error =~ "no coinmarketcap integer id"
    end
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

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_concurrency: 1)

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :finished
      assert srp.progress_datetime == ~N[2023-07-21 00:00:00]
      assert srp.last_error == nil

      assert requested_ranges() == [
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-19 00:00:00Z], ~U[2023-07-20 00:00:00Z]},
               {~U[2023-07-20 00:00:00Z], ~U[2023-07-21 00:00:00Z]}
             ]
    end

    test "after too many failures the rescrape is marked as failed", context do
      mock_cmc(fn -> %Tesla.Env{status: 500, body: "boom"} end)

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_failures: 3)

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :failed
      assert srp.progress_datetime == nil
      assert srp.last_error =~ "Status: 500"
    end

    test "a crash while fetching is handled as an error", context do
      mock_cmc(fn -> exit(:boom) end)

      {:ok, srp} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_failures: 1)

      {:ok, srp} = ScheduleRescrapePrice.by_id(srp.id)
      assert srp.status == :failed
      assert srp.last_error =~ "exited"
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

      {:ok, _} =
        create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00],
          priority: :low
        )

      {:ok, _} =
        create_rescrape(ethereum, ~N[2023-07-19 00:00:00], ~N[2023-07-22 00:00:00],
          priority: :high
        )

      run_scheduler(max_concurrency: 1)

      assert requested_cmc_ids() == [1027, 1027, 1027, 1, 1, 1]
    end
  end

  test "the cursor cannot be moved from a stale position", context do
    {:ok, srp} =
      create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

    # Two schedulers read the same rescrape, the first one moves the cursor
    assert {:ok, _} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])

    assert {:error, :not_active} =
             ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])
  end

  test "does not start when disabled" do
    assert :ignore = RescrapeScheduler.init(enabled?: false)
  end

  # Run the scheduler until there is nothing left to fetch
  defp run_scheduler(opts \\ []) do
    opts =
      Keyword.merge(
        [enabled?: true, notify: self(), retry_after_ms: 0, refresh_interval_ms: 60_000],
        opts
      )

    pid = start_supervised!({RescrapeScheduler, opts})
    assert_receive {:rescrape_scheduler, :idle}, 5_000
    pid
  end

  defp create_rescrape(project, from, to, opts \\ []) do
    ScheduleRescrapePrice.create(%{
      project_id: project.id,
      from: from,
      to: to,
      priority: Keyword.get(opts, :priority, :normal)
    })
  end

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

  defp empty_points_response() do
    %{
      "data" => %{"points" => %{}},
      "status" => %{"error_code" => "0", "error_message" => "SUCCESS"}
    }
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
