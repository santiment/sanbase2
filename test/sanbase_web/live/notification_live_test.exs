defmodule SanbaseWeb.NotificationLiveTest do
  use SanbaseWeb.ConnCase

  import Phoenix.LiveViewTest
  import Sanbase.NotificationsFixtures

  @create_attrs %{
    status: "some status",
    step: "some step",
    channels: ["option1", "option2"],
    scheduled_at: "2024-10-17T07:56:00Z",
    sent_at: "2024-10-17T07:56:00Z",
    content: "some content",
    display_in_ui: true,
    template_params: %{}
  }
  @update_attrs %{
    status: "some updated status",
    step: "some updated step",
    channels: ["option1"],
    scheduled_at: "2024-10-18T07:56:00Z",
    sent_at: "2024-10-18T07:56:00Z",
    content: "some updated content",
    display_in_ui: false,
    template_params: %{}
  }
  @invalid_attrs %{
    status: nil,
    step: nil,
    channels: [],
    scheduled_at: nil,
    sent_at: nil,
    content: nil,
    display_in_ui: false,
    template_params: nil
  }

  defp create_notification(_) do
    notification = notification_fixture()
    %{notification: notification}
  end

  describe "Index" do
    setup [:create_notification]

    test "lists all notifications", %{conn: conn, notification: notification} do
      {:ok, _index_live, html} = live(conn, ~p"/admin2/notifications")

      assert html =~ "Listing Notifications"
      assert html =~ notification.status
    end

    test "saves new notification", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/admin2/notifications")

      assert index_live |> element("a", "New Notification") |> render_click() =~
               "New Notification"

      assert_patch(index_live, ~p"/admin2/notifications/new")

      assert index_live
             |> form("#notification-form", notification: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#notification-form", notification: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin2/notifications")

      html = render(index_live)
      assert html =~ "Notification created successfully"
      assert html =~ "some status"
    end

    test "updates notification in listing", %{conn: conn, notification: notification} do
      {:ok, index_live, _html} = live(conn, ~p"/admin2/notifications")

      assert index_live
             |> element("#notifications-#{notification.id} a", "Edit")
             |> render_click() =~
               "Edit Notification"

      assert_patch(index_live, ~p"/admin2/notifications/#{notification}/edit")

      assert index_live
             |> form("#notification-form", notification: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#notification-form", notification: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/admin2/notifications")

      html = render(index_live)
      assert html =~ "Notification updated successfully"
      assert html =~ "some updated status"
    end

    test "deletes notification in listing", %{conn: conn, notification: notification} do
      {:ok, index_live, _html} = live(conn, ~p"/admin2/notifications")

      assert index_live
             |> element("#notifications-#{notification.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#notifications-#{notification.id}")
    end
  end

  describe "Show" do
    setup [:create_notification]

    test "displays notification", %{conn: conn, notification: notification} do
      {:ok, _show_live, html} = live(conn, ~p"/admin2/notifications/#{notification}")

      assert html =~ "Show Notification"
      assert html =~ notification.status
    end

    test "updates notification within modal", %{conn: conn, notification: notification} do
      {:ok, show_live, _html} = live(conn, ~p"/admin2/notifications/#{notification}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Notification"

      assert_patch(show_live, ~p"/admin2/notifications/#{notification}/show/edit")

      assert show_live
             |> form("#notification-form", notification: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#notification-form", notification: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/admin2/notifications/#{notification}")

      html = render(show_live)
      assert html =~ "Notification updated successfully"
      assert html =~ "some updated status"
    end
  end
end
