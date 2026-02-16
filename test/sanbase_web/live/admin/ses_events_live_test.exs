defmodule SanbaseWeb.Admin.SesEventsLiveTest do
  use SanbaseWeb.ConnCase, async: false

  @moduletag capture_log: true

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Email.SesEmailEvent

  setup do
    user = insert(:user)
    admin_role = insert(:role_admin_panel_viewer)
    {:ok, _user_role} = Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    {:ok, conn: conn}
  end

  defp insert_event(attrs) do
    defaults = %{
      message_id: "msg-#{System.unique_integer([:positive])}",
      email: "test@example.com",
      event_type: "Delivery",
      timestamp: DateTime.utc_now()
    }

    {:ok, event} = SesEmailEvent.create(Map.merge(defaults, attrs))
    event
  end

  describe "mount" do
    test "renders the page with title", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/ses_events")
      assert html =~ "SES Email Events"
    end

    test "shows empty state when no events exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, "/admin/ses_events")
      assert html =~ "No events found matching your filters"
    end

    test "displays events in the table", %{conn: conn} do
      insert_event(%{email: "alice@example.com", event_type: "Send"})
      insert_event(%{email: "bob@example.com", event_type: "Bounce", bounce_type: "Permanent"})

      {:ok, _view, html} = live(conn, "/admin/ses_events")
      assert html =~ "alice@example.com"
      assert html =~ "bob@example.com"
      assert html =~ "Send"
      assert html =~ "Bounce"
    end
  end

  describe "filtering" do
    setup %{conn: conn} do
      insert_event(%{email: "alice@example.com", event_type: "Send"})
      insert_event(%{email: "alice@example.com", event_type: "Delivery"})
      insert_event(%{email: "bob@example.com", event_type: "Bounce", bounce_type: "Permanent"})

      {:ok, view, _html} = live(conn, "/admin/ses_events")
      {:ok, view: view}
    end

    test "filters by event type", %{view: view} do
      html =
        view
        |> element("#event-type-filter")
        |> render_change(%{"event_type" => "Bounce"})

      assert html =~ "bob@example.com"
      refute html =~ "alice@example.com"
    end

    test "filters by email search", %{view: view} do
      html =
        view
        |> element("#email-search-form")
        |> render_change(%{"email_search" => "alice"})

      assert html =~ "alice@example.com"
      refute html =~ "bob@example.com"
    end

    test "shows all when filter is cleared", %{view: view} do
      view
      |> element("#event-type-filter")
      |> render_change(%{"event_type" => "Bounce"})

      html =
        view
        |> element("#event-type-filter")
        |> render_change(%{"event_type" => ""})

      assert html =~ "alice@example.com"
      assert html =~ "bob@example.com"
    end
  end

  describe "pagination" do
    test "paginates through events", %{conn: conn} do
      for i <- 1..55 do
        insert_event(%{
          email: "user#{String.pad_leading("#{i}", 3, "0")}@example.com",
          event_type: "Send"
        })
      end

      {:ok, view, html} = live(conn, "/admin/ses_events")
      assert html =~ "Page 1 of 2"

      html = render_click(view, "next_page")
      assert html =~ "Page 2 of 2"

      html = render_click(view, "prev_page")
      assert html =~ "Page 1 of 2"
    end
  end

  describe "raw data toggle" do
    test "expands and collapses raw data", %{conn: conn} do
      event =
        insert_event(%{
          email: "raw@example.com",
          event_type: "Bounce",
          raw_data: %{"bounce" => %{"bounceType" => "Permanent"}}
        })

      {:ok, view, html} = live(conn, "/admin/ses_events")
      refute html =~ "bounceType"

      html = render_click(view, "toggle_raw", %{"id" => "#{event.id}"})
      assert html =~ "bounceType"
      assert html =~ "Permanent"

      html = render_click(view, "toggle_raw", %{"id" => "#{event.id}"})
      refute html =~ "bounceType"
    end
  end

  describe "stats bar" do
    test "shows event type counts", %{conn: conn} do
      insert_event(%{event_type: "Send"})
      insert_event(%{event_type: "Send"})
      insert_event(%{event_type: "Delivery"})
      insert_event(%{event_type: "Bounce", bounce_type: "Permanent"})

      {:ok, _view, html} = live(conn, "/admin/ses_events")
      assert html =~ "Send (24h)"
      assert html =~ "Delivery (24h)"
      assert html =~ "Bounce (24h)"
    end
  end
end
