defmodule SanbaseWeb.Admin.PriceRescrapesLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  setup do
    bitcoin = insert_cmc_project("bitcoin", "Bitcoin", 1)
    ethereum = insert_cmc_project("ethereum", "Ethereum", 2)

    [bitcoin: bitcoin, ethereum: ethereum]
  end

  describe "an admin panel editor" do
    setup do
      [conn: login(:role_admin_panel_editor)]
    end

    test "lists the active rescrapes with their progress", context do
      srp = create_rescrape(context.bitcoin)
      {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])

      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      assert has_element?(view, "#rescrapes-#{srp.id}", "bitcoin")
      assert has_element?(view, "#rescrapes-#{srp.id}", "50%")
      assert has_element?(view, "#rescrapes-#{srp.id}", "waiting for a free slot")
      assert has_element?(view, "#status-tile-pending", "1")
      assert has_element?(view, "#schedule-form")
    end

    test "filters the rescrapes by status", context do
      active = create_rescrape(context.bitcoin)
      finished = create_rescrape(context.ethereum)
      {:ok, _} = ScheduleRescrapePrice.mark_finished(finished)

      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      assert has_element?(view, "#rescrapes-#{active.id}")
      refute has_element?(view, "#rescrapes-#{finished.id}")

      view |> element("#status-tile-finished") |> render_click()

      refute has_element?(view, "#rescrapes-#{active.id}")
      assert has_element?(view, "#rescrapes-#{finished.id}")
    end

    test "schedules rescrapes for the picked projects", context do
      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      view
      |> form("#project-search-form", %{project_search: "bitcoin, ethereum, unknown-coin"})
      |> render_submit()

      assert has_element?(view, "#selected-bitcoin")
      assert has_element?(view, "#selected-ethereum")
      assert has_element?(view, "#unknown-slugs", "unknown-coin")

      view
      |> form("#schedule-form", %{
        rescrape: %{from: "2023-07-19T00:00", to: "2023-07-21T00:00", priority: "high"}
      })
      |> render_submit()

      assert render_async(view) =~ "Scheduled"
      assert has_element?(view, "#schedule-result-created", "2")

      rescrapes = ScheduleRescrapePrice.list()
      assert length(rescrapes) == 2
      assert Enum.all?(rescrapes, &(&1.priority == :high and &1.from == ~N[2023-07-19 00:00:00]))

      for srp <- rescrapes do
        assert has_element?(view, "#rescrapes-#{srp.id}")
      end
    end

    test "picks a project from the suggestions", context do
      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      view |> form("#project-search-form", %{project_search: "ether"}) |> render_change()
      view |> element("#suggestion-ethereum") |> render_click()

      assert has_element?(view, "#selected-ethereum")
      refute has_element?(view, "#selected-bitcoin")
    end

    test "lists the projects that could not be scheduled", context do
      _existing = create_rescrape(context.bitcoin)

      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      view
      |> form("#project-search-form", %{project_search: "bitcoin ethereum"})
      |> render_submit()

      view
      |> form("#schedule-form", %{
        rescrape: %{from: "2023-08-01T00:00", to: "2023-08-02T00:00", priority: "normal"}
      })
      |> render_submit()

      render_async(view)

      assert has_element?(view, "#schedule-result-created", "1")
      assert has_element?(view, "#schedule-result-errors", "already has an active")
      # The project that failed stays picked
      assert has_element?(view, "#selected-bitcoin")
      refute has_element?(view, "#selected-ethereum")
    end

    test "does not schedule an interval that ends before it starts", context do
      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      view |> form("#project-search-form", %{project_search: "bitcoin"}) |> render_submit()

      html =
        view
        |> form("#schedule-form", %{
          rescrape: %{from: "2023-08-02T00:00", to: "2023-08-01T00:00", priority: "normal"}
        })
        |> render_submit()

      assert html =~ "must be after `from`"
      assert ScheduleRescrapePrice.list() == []
    end

    test "changes the priority, cancels and resumes a rescrape", context do
      srp = create_rescrape(context.bitcoin)

      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      view
      |> form("#priority-form-#{srp.id}", %{priority: "low"})
      |> render_change()

      assert reload(srp).priority == :low

      view |> element("#cancel-#{srp.id}") |> render_click()
      assert reload(srp).status == :cancelled

      view |> element("#status-tile-cancelled") |> render_click()
      view |> element("#resume-#{srp.id}") |> render_click()
      assert reload(srp).status == :pending
    end
  end

  describe "an admin panel viewer" do
    setup do
      [conn: login(:role_admin_panel_viewer)]
    end

    test "can follow the rescrapes but not change them", context do
      srp = create_rescrape(context.bitcoin)

      {:ok, view, _html} = live(context.conn, "/admin/price_rescrapes")

      assert has_element?(view, "#rescrapes-#{srp.id}")
      assert has_element?(view, "#read-only-notice")
      refute has_element?(view, "#schedule-form")
      refute has_element?(view, "#cancel-#{srp.id}")

      # A crafted event is rejected too
      render_click(view, "cancel", %{"id" => to_string(srp.id)})
      assert reload(srp).status == :pending
    end
  end

  test "the page is listed in the admin forms", _context do
    {:ok, view, _html} = live(login(:role_admin_panel_viewer), "/admin/admin_forms")
    assert has_element?(view, ~s|a[href="/admin/price_rescrapes"]|)
  end

  defp login(role_factory) do
    user = insert(:user)
    role = insert(role_factory)
    Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    Plug.Test.init_test_session(build_conn(), jwt_tokens)
  end

  defp insert_cmc_project(slug, name, rank) do
    insert(:latest_cmc_data, %{coinmarketcap_id: slug, rank: rank})
    insert(:project, %{slug: slug, name: name})
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
end
