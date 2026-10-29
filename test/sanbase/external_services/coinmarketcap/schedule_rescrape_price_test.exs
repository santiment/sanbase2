defmodule Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePriceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  setup do
    bitcoin = insert_cmc_project("bitcoin", "Bitcoin", "BTC", 1)
    ethereum = insert_cmc_project("ethereum", "Ethereum", "ETH", 2)

    _not_cmc =
      insert(:project, %{
        slug: "not_cmc_coin",
        name: "Not CMC Coin",
        source_slug_mappings: [
          build(:source_slug_mapping, %{source: "cryptocompare", slug: "NOTCMC"})
        ]
      })

    [bitcoin: bitcoin, ethereum: ethereum]
  end

  describe "cancel/1" do
    test "cancels an active rescrape", context do
      srp = create_rescrape(context.bitcoin)

      assert {:ok, _} = ScheduleRescrapePrice.cancel(srp)
      assert %{status: :cancelled, finished_at: %NaiveDateTime{}} = reload(srp)
    end

    test "does not cancel a finished rescrape", context do
      srp = create_rescrape(context.bitcoin)
      {:ok, srp} = ScheduleRescrapePrice.mark_finished(srp)

      assert {:error, :not_active} = ScheduleRescrapePrice.cancel(srp)
      assert reload(srp).status == :finished
    end
  end

  describe "resume/1" do
    test "a failed rescrape goes back to pending and keeps its cursor", context do
      srp = create_rescrape(context.bitcoin)
      {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])
      {:ok, srp} = ScheduleRescrapePrice.mark_failed(srp, "boom")

      assert {:ok, _} = ScheduleRescrapePrice.resume(srp)

      assert %{
               status: :pending,
               finished_at: nil,
               last_error: nil,
               progress_datetime: ~N[2023-07-20 00:00:00]
             } = reload(srp)
    end

    test "a cancelled rescrape cannot be resumed while another one is active", context do
      srp = create_rescrape(context.bitcoin)
      {:ok, srp} = ScheduleRescrapePrice.cancel(srp)
      _other = create_rescrape(context.bitcoin)

      assert {:error, changeset} = ScheduleRescrapePrice.resume(reload(srp))

      assert %{project_id: ["already has an active (pending or running) rescrape"]} =
               errors_on(changeset)
    end

    test "an active rescrape cannot be resumed", context do
      srp = create_rescrape(context.bitcoin)
      assert {:error, _} = ScheduleRescrapePrice.resume(srp)
    end
  end

  describe "update_priority/2" do
    test "updates the priority", context do
      srp = create_rescrape(context.bitcoin)

      assert {:ok, %{priority: :high}} = ScheduleRescrapePrice.update_priority(srp, "high")
      assert reload(srp).priority == :high
    end

    test "rejects an unknown priority", context do
      srp = create_rescrape(context.bitcoin)
      assert {:error, %Ecto.Changeset{}} = ScheduleRescrapePrice.update_priority(srp, "urgent")
    end
  end

  describe "list/1 and status_counts/0" do
    test "filters by status and project", context do
      btc = create_rescrape(context.bitcoin)
      eth = create_rescrape(context.ethereum)
      {:ok, _} = ScheduleRescrapePrice.mark_finished(eth)

      assert ids(ScheduleRescrapePrice.list()) == [btc.id, eth.id]
      assert ids(ScheduleRescrapePrice.list(status: :active)) == [btc.id]
      assert ids(ScheduleRescrapePrice.list(status: :finished)) == [eth.id]
      assert ids(ScheduleRescrapePrice.list(search: "ether")) == [eth.id]
      assert ids(ScheduleRescrapePrice.list(search: "%")) == []

      assert ScheduleRescrapePrice.status_counts() == %{pending: 1, finished: 1}
    end

    test "running rescrapes come first", context do
      btc = create_rescrape(context.bitcoin)
      eth = create_rescrape(context.ethereum)
      {:ok, _} = ScheduleRescrapePrice.mark_running(btc)

      assert ids(ScheduleRescrapePrice.list()) == [btc.id, eth.id]
    end
  end

  describe "progress/2" do
    test "is the part of the interval before the cursor", context do
      srp = create_rescrape(context.bitcoin)
      now = ~N[2030-01-01 00:00:00]

      assert ScheduleRescrapePrice.progress(srp, now) == 0.0

      {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])
      assert ScheduleRescrapePrice.progress(srp, now) == 0.5

      {:ok, srp} = ScheduleRescrapePrice.mark_finished(srp)
      assert ScheduleRescrapePrice.progress(srp, now) == 1.0
    end

    test "an interval that ends in the future is measured until now", context do
      srp = create_rescrape(context.bitcoin)
      {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-19 12:00:00])

      assert ScheduleRescrapePrice.progress(srp, ~N[2023-07-20 00:00:00]) == 0.5
    end
  end

  describe "project search" do
    test "search_projects/2 finds coinmarketcap projects by slug, name or ticker" do
      assert slugs(ScheduleRescrapePrice.search_projects("eth", 10)) == ["ethereum"]
      assert slugs(ScheduleRescrapePrice.search_projects("BTC", 10)) == ["bitcoin"]
      assert slugs(ScheduleRescrapePrice.search_projects("coin", 10)) == ["bitcoin"]
      assert slugs(ScheduleRescrapePrice.search_projects("", 10)) == ["bitcoin", "ethereum"]
      assert slugs(ScheduleRescrapePrice.search_projects("_", 10)) == []
    end

    test "projects_by_slugs/1 skips projects not scraped from coinmarketcap" do
      assert slugs(ScheduleRescrapePrice.projects_by_slugs(["ethereum", "not_cmc_coin", "x"])) ==
               ["ethereum"]
    end
  end

  defp insert_cmc_project(slug, name, ticker, rank) do
    insert(:latest_cmc_data, %{coinmarketcap_id: slug, rank: rank})

    insert(:project, %{
      slug: slug,
      name: name,
      ticker: ticker,
      source_slug_mappings: [build(:source_slug_mapping, %{source: "coinmarketcap", slug: slug})]
    })
  end

  defp create_rescrape(project) do
    {:ok, srp} =
      ScheduleRescrapePrice.create(%{
        project_id: project.id,
        from: ~N[2023-07-19 00:00:00],
        to: ~N[2023-07-21 00:00:00]
      })

    srp
  end

  defp reload(srp), do: Sanbase.Repo.get!(ScheduleRescrapePrice, srp.id)
  defp ids(rescrapes), do: Enum.map(rescrapes, & &1.id)
  defp slugs(projects), do: Enum.map(projects, & &1.slug)
end
