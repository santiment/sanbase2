defmodule SanbaseWeb.TagLiveTest do
  use SanbaseWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Sanbase.Factory

  alias Sanbase.Metric.Tag

  setup do
    user = insert(:user)
    metric_registry_role = insert(:role_metric_registry_owner)
    admin_role = insert(:role_admin_panel_viewer)
    Sanbase.Accounts.UserRole.create(user.id, metric_registry_role.id)
    Sanbase.Accounts.UserRole.create(user.id, admin_role.id)
    {:ok, jwt_tokens} = SanbaseWeb.Guardian.get_jwt_tokens(user)
    conn = Plug.Test.init_test_session(build_conn(), jwt_tokens)

    {:ok, tag} = Tag.create_tag(%{name: "basic_test_tag", description: "tag for tests"})

    {:ok, conn: conn, tag: tag}
  end

  describe "tagging dashboard" do
    test "renders the metrics table", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags")

      assert has_element?(view, "div", "Metric Tagging")
      assert has_element?(view, "td div", "price_usd")
      assert has_element?(view, ~s|button[phx-click="add_tag"]|, "basic_test_tag")
    end

    test "adding and removing a tag on a code metric", %{conn: conn, tag: tag} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags")

      view
      |> element(
        ~s|button[phx-click="add_tag"][phx-value-metric="price_usd"][phx-value-tag_id="#{tag.id}"]|
      )
      |> render_click()

      assert Enum.any?(Tag.list_mappings_by_tag(tag.id), &(&1.metric == "price_usd"))

      mapping = Tag.list_mappings_by_tag(tag.id) |> Enum.find(&(&1.metric == "price_usd"))

      view
      |> element(~s|button[phx-click="remove_tag"][phx-value-mapping_id="#{mapping.id}"]|)
      |> render_click()

      refute Enum.any?(Tag.list_mappings_by_tag(tag.id), &(&1.metric == "price_usd"))
    end

    test "filters by not-tagged status", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags")

      view
      |> element("form[phx-change=\"filter\"]")
      |> render_change(%{"status" => "not_tagged"})

      assert has_element?(view, "td div", "price_usd")
    end

    test "tagged row stays visible and highlighted under the not_tagged filter", %{
      conn: conn,
      tag: tag
    } do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags")

      view
      |> element("form[phx-change=\"filter\"]")
      |> render_change(%{"status" => "not_tagged"})

      # Tagging the metric makes it stop matching the filter, but the row is
      # kept visible and marked as changed so the action can be undone in place
      view
      |> element(
        ~s|button[phx-click="add_tag"][phx-value-metric="price_usd"][phx-value-tag_id="#{tag.id}"]|
      )
      |> render_click()

      assert has_element?(view, "td div", "price_usd")
      assert has_element?(view, "span.badge", "changed")
      assert has_element?(view, ~s|tr[class*="bg-info/10"]|)

      # Changing the filters drops the pinned row
      view
      |> element("form[phx-change=\"filter\"]")
      |> render_change(%{"status" => "not_tagged", "search" => "price"})

      refute has_element?(view, ~s|tr[class*="bg-info/10"]|)
      refute has_element?(view, "span.badge", "changed")
    end
  end

  describe "manage tags page" do
    test "lists tags", %{conn: conn} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags/manage")

      assert has_element?(view, "div", "Manage Tags")
      assert has_element?(view, "td span.badge", "basic_test_tag")
    end

    test "deletes a tag", %{conn: conn, tag: tag} do
      {:ok, view, _html} = live(conn, "/admin/metric_registry/tags/manage")

      view
      |> element(~s|button[phx-click="delete"][phx-value-id="#{tag.id}"]|)
      |> render_click()

      assert {:error, _} = Tag.get_tag(tag.id)
    end
  end
end
