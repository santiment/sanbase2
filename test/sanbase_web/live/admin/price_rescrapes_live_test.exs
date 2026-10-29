defmodule SanbaseWeb.Admin.PriceRescrapesLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.ExternalServices.Coinmarketcap.ScheduleRescrapePrice

  setup do
    [project | _] =
      for slug <- ["bitcoin", "ethereum"] do
        insert(:latest_cmc_data, %{coinmarketcap_id: slug})
        insert(:project, %{slug: slug, name: String.capitalize(slug)})
      end

    [project: project]
  end

  test "an editor schedules rescrapes for pasted slugs" do
    {:ok, view, _html} = live(login(:role_admin_panel_editor), "/admin/price_rescrapes")

    view
    |> form("#project-search-form", %{project_search: "bitcoin, ethereum"})
    |> render_submit()

    assert has_element?(view, "#selected-ethereum")

    view
    |> form("#schedule-form", %{
      rescrape: %{from: "2023-07-19T00:00", to: "2023-07-21T00:00", priority: "high"}
    })
    |> render_submit()

    render_async(view)

    rescrapes = ScheduleRescrapePrice.list()
    assert [%{priority: :high}, %{priority: :high}] = rescrapes
    assert Enum.all?(rescrapes, &has_element?(view, "#rescrapes-#{&1.id}"))
    refute has_element?(view, "#selected-ethereum")
  end

  test "an editor changes the priority, cancels and resumes a rescrape", context do
    srp = create_rescrape(context.project)
    {:ok, srp} = ScheduleRescrapePrice.advance_cursor(srp, ~N[2023-07-20 00:00:00])

    {:ok, view, _html} = live(login(:role_admin_panel_editor), "/admin/price_rescrapes")
    assert has_element?(view, "#rescrapes-#{srp.id}", "50%")

    view |> form("#priority-form-#{srp.id}", %{priority: "low"}) |> render_change()
    assert reload(srp).priority == :low

    view |> element("#cancel-#{srp.id}") |> render_click()
    assert reload(srp).status == :cancelled
    refute has_element?(view, "#rescrapes-#{srp.id}")

    view |> element("#status-tile-cancelled") |> render_click()
    view |> element("#resume-#{srp.id}") |> render_click()
    assert reload(srp).status == :pending
  end

  test "a viewer can follow the rescrapes but not change them", context do
    srp = create_rescrape(context.project)

    conn = login(:role_admin_panel_viewer)
    {:ok, view, _html} = live(conn, "/admin/price_rescrapes")

    assert has_element?(view, "#rescrapes-#{srp.id}", "waiting for a free slot")
    assert has_element?(view, "#read-only-notice")
    refute has_element?(view, "#schedule-form")

    render_click(view, "cancel", %{"id" => to_string(srp.id)})
    assert reload(srp).status == :pending

    {:ok, view, _html} = live(conn, "/admin/admin_forms")
    assert has_element?(view, ~s|a[href="/admin/price_rescrapes"]|)
  end

  defp login(role_factory) do
    user = insert(:user)
    role = insert(role_factory)
    Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    Plug.Test.init_test_session(build_conn(), jwt_tokens)
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
