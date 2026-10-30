defmodule Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePriceTest do
  use Sanbase.DataCase, async: false

  import Sanbase.Factory

  alias Sanbase.Repo
  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  setup do
    [bitcoin, ethereum] =
      for {slug, ticker, rank} <- [{"bitcoin", "BTC", 1}, {"ethereum", "ETH", 2}] do
        insert(:latest_cmc_data, %{coinmarketcap_id: slug, rank: rank})
        insert(:project, %{slug: slug, name: String.capitalize(slug), ticker: ticker})
      end

    insert(:project, %{
      slug: "not_cmc",
      source_slug_mappings: [build(:source_slug_mapping, %{source: "cryptocompare", slug: "X"})]
    })

    [bitcoin: bitcoin, ethereum: ethereum]
  end

  test "cancel, resume and change the priority", context do
    srp = create_rescrape(context.bitcoin)
    {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])

    assert {:error, _} = ScheduleRescrapePrice.resume(srp)
    assert {:ok, _} = ScheduleRescrapePrice.cancel(srp)
    assert {:error, :not_active} = ScheduleRescrapePrice.cancel(srp)

    # Resumes from the cursor
    assert {:ok, _} = ScheduleRescrapePrice.resume(reload(srp))
    assert %{status: :pending, progress_datetime: ~N[2023-07-20 00:00:00]} = reload(srp)

    assert {:ok, %{priority: :high}} = ScheduleRescrapePrice.update_priority(srp, "high")
    assert {:error, _} = ScheduleRescrapePrice.update_priority(srp, "urgent")
  end

  test "a rescrape cannot be resumed while another one is active", context do
    srp = create_rescrape(context.bitcoin)
    {:ok, _} = ScheduleRescrapePrice.cancel(srp)
    _other = create_rescrape(context.bitcoin)

    assert {:error, changeset} = ScheduleRescrapePrice.resume(reload(srp))

    assert %{project_id: ["already has an active (pending or running) rescrape"]} =
             errors_on(changeset)
  end

  test "list/1 and status_counts/0", context do
    btc = create_rescrape(context.bitcoin)
    eth = create_rescrape(context.ethereum)
    {:ok, _} = ScheduleRescrapePrice.mark_finished(btc)

    # The active rescrapes come first
    assert ids(ScheduleRescrapePrice.list()) == [eth.id, btc.id]
    assert ids(ScheduleRescrapePrice.list(status: :active)) == [eth.id]
    assert ids(ScheduleRescrapePrice.list(search: "bitc")) == [btc.id]
    assert ScheduleRescrapePrice.status_counts() == %{pending: 1, finished: 1}
  end

  test "progress/2 is measured until now when `to` is in the future", context do
    srp = create_rescrape(context.bitcoin)
    assert ScheduleRescrapePrice.progress(srp, ~N[2030-01-01 00:00:00]) == 0.0

    {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])
    assert ScheduleRescrapePrice.progress(srp, ~N[2030-01-01 00:00:00]) == 0.5
    assert ScheduleRescrapePrice.progress(srp, ~N[2023-07-20 12:00:00]) == 1 / 1.5
    # The interval has not started yet
    assert ScheduleRescrapePrice.progress(srp, ~N[2023-07-18 00:00:00]) == 0.0
  end

  test "status edits from the generic admin set the lifecycle fields", context do
    srp = create_rescrape(context.bitcoin)

    {:ok, srp} =
      srp |> ScheduleRescrapePrice.update_changeset(%{status: :cancelled}) |> Repo.update()

    assert %NaiveDateTime{} = srp.finished_at

    {:ok, srp} =
      srp |> ScheduleRescrapePrice.update_changeset(%{status: :pending}) |> Repo.update()

    assert %{finished_at: nil, last_error: nil} = srp
  end

  test "finds the coinmarketcap projects by slug, name or ticker" do
    assert slugs(ScheduleRescrapePrice.search_projects("BTC", 10)) == ["bitcoin"]
    assert slugs(ScheduleRescrapePrice.search_projects("eum", 10)) == ["ethereum"]
    assert slugs(ScheduleRescrapePrice.search_projects("_", 10)) == []
    assert slugs(ScheduleRescrapePrice.projects_by_slugs(["ethereum", "not_cmc"])) == ["ethereum"]
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

  defp reload(srp), do: Repo.get!(ScheduleRescrapePrice, srp.id)
  defp ids(rescrapes), do: Enum.map(rescrapes, & &1.id)
  defp slugs(projects), do: Enum.map(projects, & &1.slug)
end
