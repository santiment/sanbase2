defmodule SanbaseWeb.NotificationActionLiveTest do
  use SanbaseWeb.ConnCase

  import Phoenix.LiveViewTest
  import Sanbase.NotificationsFixtures

  @create_attrs %{
    status: "some status",
    action_type: "some action_type",
    scheduled_at: "2024-10-17T07:48:00Z",
    requires_verification: true,
    verified: true
  }
  @update_attrs %{
    status: "some updated status",
    action_type: "some updated action_type",
    scheduled_at: "2024-10-18T07:48:00Z",
    requires_verification: false,
    verified: false
  }
  @invalid_attrs %{
    status: nil,
    action_type: nil,
    scheduled_at: nil,
    requires_verification: false,
    verified: false
  }

  defp create_notification_action(_) do
    notification_action = notification_action_fixture()
    %{notification_action: notification_action}
  end

  describe "Index" do
    setup [:create_notification_action]

    test "lists all notification_actions", %{conn: conn, notification_action: notification_action} do
      {:ok, _index_live, html} = live(conn, ~p"/notification_actions")

      assert html =~ "Listing Notification actions"
      assert html =~ notification_action.status
    end

    test "saves new notification_action", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/notification_actions")

      assert index_live |> element("a", "New Notification action") |> render_click() =~
               "New Notification action"

      assert_patch(index_live, ~p"/notification_actions/new")

      assert index_live
             |> form("#notification_action-form", notification_action: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#notification_action-form", notification_action: @create_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/notification_actions")

      html = render(index_live)
      assert html =~ "Notification action created successfully"
      assert html =~ "some status"
    end

    test "updates notification_action in listing", %{
      conn: conn,
      notification_action: notification_action
    } do
      {:ok, index_live, _html} = live(conn, ~p"/notification_actions")

      assert index_live
             |> element("#notification_actions-#{notification_action.id} a", "Edit")
             |> render_click() =~
               "Edit Notification action"

      assert_patch(index_live, ~p"/notification_actions/#{notification_action}/edit")

      assert index_live
             |> form("#notification_action-form", notification_action: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#notification_action-form", notification_action: @update_attrs)
             |> render_submit()

      assert_patch(index_live, ~p"/notification_actions")

      html = render(index_live)
      assert html =~ "Notification action updated successfully"
      assert html =~ "some updated status"
    end

    test "deletes notification_action in listing", %{
      conn: conn,
      notification_action: notification_action
    } do
      {:ok, index_live, _html} = live(conn, ~p"/notification_actions")

      assert index_live
             |> element("#notification_actions-#{notification_action.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#notification_actions-#{notification_action.id}")
    end
  end

  describe "Show" do
    setup [:create_notification_action]

    test "displays notification_action", %{conn: conn, notification_action: notification_action} do
      {:ok, _show_live, html} = live(conn, ~p"/notification_actions/#{notification_action}")

      assert html =~ "Show Notification action"
      assert html =~ notification_action.status
    end

    test "updates notification_action within modal", %{
      conn: conn,
      notification_action: notification_action
    } do
      {:ok, show_live, _html} = live(conn, ~p"/notification_actions/#{notification_action}")

      assert show_live |> element("a", "Edit") |> render_click() =~
               "Edit Notification action"

      assert_patch(show_live, ~p"/notification_actions/#{notification_action}/show/edit")

      assert show_live
             |> form("#notification_action-form", notification_action: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert show_live
             |> form("#notification_action-form", notification_action: @update_attrs)
             |> render_submit()

      assert_patch(show_live, ~p"/notification_actions/#{notification_action}")

      html = render(show_live)
      assert html =~ "Notification action updated successfully"
      assert html =~ "some updated status"
    end
  end
end
