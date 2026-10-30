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
      counter = start_supervised!({Agent, fn -> 0 end})
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

    test "a DB error does not crash the scheduler", context do
      mock_cmc_success()
      srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-20 00:00:00])

      # A value that cannot be loaded makes every reload of the rescrapes raise
      set_priority_sql = "UPDATE schedule_rescrape_prices SET priority = $1 WHERE id = $2"
      Sanbase.Repo.query!(set_priority_sql, ["urgent", srp.id])

      pid = start_scheduler()
      ref = Process.monitor(pid)
      assert_receive {:rescrape_scheduler, :idle}, 5_000
      assert %{status: :pending} = reload_raw(srp)

      Sanbase.Repo.query!(set_priority_sql, ["normal", srp.id])
      send(pid, :refresh)
      assert_receive {:rescrape_scheduler, :idle}, 5_000

      refute_received {:DOWN, ^ref, :process, _, _}
      assert %{status: :finished} = reload(srp)
    end

    test "a crash while fetching is handled as an error", context do
      mock_cmc(fn -> exit(:boom) end)

      srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-21 00:00:00])

      run_scheduler(max_failures: 1)

      assert %{status: :failed, last_error: "" <> error} = reload(srp)
      assert error =~ "exited"
    end
  end

  test "a rescrape whose `from` is in the future waits until then", context do
    mock_cmc_success()
    from = NaiveDateTime.utc_now() |> NaiveDateTime.add(86_400) |> NaiveDateTime.truncate(:second)

    # The changeset does not allow it, but it can still get in the DB
    srp =
      Sanbase.Repo.insert!(%ScheduleRescrapePrice{
        project_id: context.project.id,
        from: from,
        to: NaiveDateTime.add(from, 2 * 86_400)
      })

    run_scheduler()

    assert requested_ranges() == []
    assert %{status: :pending, progress_datetime: nil} = reload(srp)
  end

  test "an old rescrape with `from` after `to` is finished without fetching", context do
    mock_cmc_success()

    # The from_before_to constraint is not validated for the old rows. Dropped
    # only in the test's transaction.
    Sanbase.Repo.query!("ALTER TABLE schedule_rescrape_prices DROP CONSTRAINT from_before_to")

    srp =
      Sanbase.Repo.insert!(%ScheduleRescrapePrice{
        project_id: context.project.id,
        from: ~N[2023-07-21 00:00:00],
        to: ~N[2023-07-19 00:00:00]
      })

    run_scheduler()

    assert requested_ranges() == []
    assert %{status: :finished} = reload(srp)
  end

  test "a rescrape cancelled and resumed between two refreshes runs again", context do
    test_pid = self()
    body = File.read!(Path.join(__DIR__, "data/btc_web_api_success2.json"))

    # Every request waits until the test lets it through
    mock_cmc(fn ->
      send(test_pid, {:request_waiting, self()})

      receive do
        :continue -> %Tesla.Env{status: 200, body: body}
      end
    end)

    srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-20 00:00:00])
    pid = start_scheduler()
    assert_receive {:request_waiting, first_request}, 5_000

    {:ok, _} = ScheduleRescrapePrice.cancel(reload(srp))
    {:ok, _} = ScheduleRescrapePrice.resume(reload(srp))
    send(pid, :refresh)
    _ = :sys.get_state(pid)

    # Started again from its cursor, the result of the first request is ignored
    assert %{status: :running} = reload(srp)
    assert_receive {:request_waiting, second_request}, 5_000

    send(first_request, :continue)
    send(second_request, :continue)
    assert_receive {:rescrape_scheduler, :idle}, 5_000
    assert %{status: :finished} = reload(srp)
  end

  test "frequent refreshes do not restart the rescrapes in progress", context do
    mock_cmc_success()
    srp = create_rescrape(context.project, ~N[2023-07-19 00:00:00], ~N[2023-07-23 00:00:00])

    run_scheduler(refresh_interval_ms: 1, max_concurrency: 1)

    assert length(requested_ranges()) == 4
    assert %{status: :finished, progress_datetime: ~N[2023-07-23 00:00:00]} = reload(srp)
  end

  test "a crash loop of the scheduler does not take down its parent supervisor" do
    children = [
      {Agent, fn -> :another_scraper end},
      RescrapeScheduler.isolated_child_spec(enabled?: true, refresh_interval_ms: 60_000)
    ]

    parent =
      start_supervised!(%{
        id: :parent,
        type: :supervisor,
        start: {Supervisor, :start_link, [children, [strategy: :one_for_one, max_restarts: 0]]}
      })

    parent_ref = Process.monitor(parent)
    {_, sibling, _, _} = List.keyfind(Supervisor.which_children(parent), Agent, 0)

    {_, rescrape_supervisor, :supervisor, _} =
      List.keyfind(Supervisor.which_children(parent), :cmc_rescrape_scheduler_supervisor, 0)

    # The rescrape supervisor exits like it does when the scheduler crashes too often
    Process.exit(rescrape_supervisor, :kill)

    refute_receive {:DOWN, ^parent_ref, :process, _, _}, 200
    assert [{Agent, ^sibling, :worker, _}] = Supervisor.which_children(parent)
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
    start_scheduler(opts)
    assert_receive {:rescrape_scheduler, :idle}, 5_000
  end

  defp start_scheduler(opts \\ []) do
    opts =
      Keyword.merge(
        [enabled?: true, notify: self(), retry_after_ms: 0, refresh_interval_ms: 60_000],
        opts
      )

    start_supervised!({RescrapeScheduler, opts})
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

  # Works when the row cannot be loaded into the schema
  defp reload_raw(srp) do
    %{rows: [[status]]} =
      Sanbase.Repo.query!("SELECT status FROM schedule_rescrape_prices WHERE id = $1", [srp.id])

    %{status: String.to_existing_atom(status)}
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
