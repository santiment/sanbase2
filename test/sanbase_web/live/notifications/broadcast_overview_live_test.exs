defmodule SanbaseWeb.NotificationsLive.BroadcastOverviewLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.AppNotifications
  alias Sanbase.AppNotifications.Notification

  @path "/admin/notifications/broadcast/overview"

  defp login_with_role(role_factory) do
    user = insert(:user)
    role = insert(role_factory)
    Sanbase.Accounts.UserRole.create(user.id, role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)
    %{conn: conn, user: user}
  end

  defp create_broadcast(title \\ "New feature") do
    {:ok, %{notification: notification}} =
      AppNotifications.create_broadcast_notification(%{
        type: "santiment_broadcast_new_features",
        title: title,
        content: "We shipped something new."
      })

    notification
  end

  describe "as an Admin Panel Editor" do
    setup do
      login_with_role(:role_admin_panel_editor)
    end

    test "soft-deletes a broadcast via the in-app confirmation modal", %{conn: conn} do
      notification = create_broadcast()

      {:ok, view, html} = live(conn, @path)

      # The broadcast and its delete button are visible
      assert html =~ "New feature"
      assert has_element?(view, "button[phx-value-id='#{notification.id}']")

      # Clicking Delete opens our own modal (server-rendered, not a native dialog)
      html = view |> element("button[phx-value-id='#{notification.id}']") |> render_click()
      assert html =~ "Delete this broadcast?"

      # Confirming performs the soft delete and removes the row
      html = view |> element("button[phx-click='confirm_delete']") |> render_click()

      refute html =~ "New feature"
      assert Sanbase.Repo.get(Notification, notification.id).is_deleted == true
    end

    test "cancelling the modal does not delete", %{conn: conn} do
      notification = create_broadcast()
      {:ok, view, _html} = live(conn, @path)

      view |> element("button[phx-value-id='#{notification.id}']") |> render_click()
      html = view |> element("button", "Cancel") |> render_click()

      refute html =~ "Delete this broadcast?"
      assert Sanbase.Repo.get(Notification, notification.id).is_deleted == false
    end
  end

  describe "as an Admin Panel Viewer" do
    setup do
      login_with_role(:role_admin_panel_viewer)
    end

    test "does not see a delete button", %{conn: conn} do
      _notification = create_broadcast()
      {:ok, view, html} = live(conn, @path)

      assert html =~ "New feature"
      refute has_element?(view, "button[phx-click='request_delete']")
    end

    test "is denied server-side even when the event is pushed directly", %{conn: conn} do
      notification = create_broadcast()
      {:ok, view, _html} = live(conn, @path)

      html =
        render_click(view, "request_delete", %{
          "id" => to_string(notification.id),
          "title" => notification.title,
          "recipients" => "1"
        })

      # No modal opened and nothing deleted
      refute html =~ "Delete this broadcast?"
      assert Sanbase.Repo.get(Notification, notification.id).is_deleted == false

      # Even a forced confirm_delete is rejected
      render_click(view, "confirm_delete", %{})
      assert Sanbase.Repo.get(Notification, notification.id).is_deleted == false
    end
  end
end
